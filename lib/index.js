/**
 * Complete reverse-skill pack as a DeepSeek Harness Cordis plugin.
 *
 * Data-driven provider: it walks the bundled `skills/` and
 * `CTF-Sandbox-Orchestrator/` trees (recursively, so nested sub-skills such as
 * pentest-tools/src-hunter and reverse-engineering/dsl-vm-reverse are discovered
 * too), exposes every SKILL.md through the `ctx.skills` seam, and serves the full
 * body on demand. No manual candidate list to keep in sync with the source pack.
 *
 * Targets the DSH 0.2.0-rc.2 skill seam (`@deepseek-ai/dsh-skill` ^0.2.0-rc.2):
 *
 *   - `registerProvider` hands the factory a `SkillProviderControl`.
 *     `control.signal` is the registration's lifecycle signal and is honoured
 *     alongside the per-call `options.signal`, so a disposed plugin or a
 *     superseded lookup stops walking the tree. `control.invalidate()` is the
 *     provider-to-registry notification and is deliberately never called: this
 *     pack's catalog is immutable for the lifetime of a registration.
 *   - `list()` returns a `SkillProviderObservation` so genuinely partial discovery
 *     can be reported. If a `readdir` under either root fails, the observation is
 *     marked `complete: false` and the catalog is not memoized, so the registry
 *     never caches a truncated catalog as authoritative.
 *   - `path` is emitted on every summary now that it lives on `SkillSummary`.
 *   - YAML block scalars (`description: |`) are parsed; several upstream SKILL.md
 *     files use them and previously lost their routing description entirely.
 *
 * Credit: the `SkillProviderControl` / `SkillProviderObservation` handling and the
 * per-registration cache scoping follow PR #7 by @chen-sky
 * (https://github.com/dhicoc/dsh-reverse-skill/pull/7), reimplemented here on the
 * 0.2.0-rc.2 seam with the block-scalar fix for issue #4 folded in.
 *
 * @module @dhicoc/dsh-reverse-skill
 */
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
// Repo layout: src/index.ts -> lib/index.js ; skills/ and CTF-Sandbox-Orchestrator/
// sit at the package root, one level above lib/. The URL below (no trailing slash,
// no extra dirname) resolves to the skills/ *directory* itself. Note: do NOT wrap in
// dirname() — `new URL('../skills/', import.meta.url)` already ends in a directory name,
// so dirname() would wrongly strip it and leave the package root (which also contains
// node_modules and would double-count every SKILL.md). This holds for both local dev
// (dsh-reverse-skill/lib) and the published package (node_modules/@dhicoc/dsh-reverse-skill/lib).
const SKILLS_ROOT = fileURLToPath(new URL('../skills', import.meta.url));
const CTF_ROOT = fileURLToPath(new URL('../CTF-Sandbox-Orchestrator', import.meta.url));
const PROVIDER_NAME = 'reverse-skill';
/**
 * Stop discovery when either the registration or the caller has been cancelled,
 * so a disposed plugin or a superseded lookup cannot keep walking the tree.
 */
function throwIfAborted(registration, options) {
    if (registration.aborted)
        throw registration.reason;
    const { signal } = options;
    if (signal?.aborted)
        throw signal.reason;
}
/** YAML block scalar indicator: `|` or `>`, optionally with chomping (- / +) and an indent digit. */
const BLOCK_SCALAR = /^([|>])[+-]?\d*$/;
/**
 * Read a YAML block scalar whose `key: |` line sits at `start - 1`.
 *
 * Upstream ships several SKILL.md files that write `description` as a block scalar
 * (issue #4). Read line-by-line, such a value parses as the literal indicator "|",
 * which leaves those skills with no usable routing description at all.
 *
 * `style` is the indicator character. Returns the joined text and the index of the
 * first line after the block.
 */
function readBlockScalar(lines, start, style) {
    const raw = [];
    let i = start;
    for (; i < lines.length; i += 1) {
        const line = lines[i];
        if (line.trim() === '') {
            raw.push('');
            continue;
        }
        // An unindented line ends the block; this includes the closing `---`.
        if (!/^[ \t]/.test(line))
            break;
        raw.push(line);
    }
    while (raw.length > 0 && raw[raw.length - 1] === '')
        raw.pop();
    // Strip the block's common indentation; blank lines do not participate.
    const indents = raw
        .filter((l) => l !== '')
        .map((l) => (l.match(/^[ \t]*/)[0]).length);
    const indent = indents.length > 0 ? Math.min(...indents) : 0;
    const text = raw.map((l) => (l === '' ? '' : l.slice(indent)));
    if (style === '|') {
        // Literal: newlines are preserved.
        return { value: text.join('\n').trim(), next: i };
    }
    // Folded: single newlines become spaces, blank lines stay as paragraph breaks.
    const folded = text.map((l, idx) => (l === '' ? '\n' : idx === 0 ? l : ` ${l}`)).join('');
    return { value: folded.replace(/\n{3,}/g, '\n\n').trim(), next: i };
}
/** Minimal YAML-frontmatter reader — enough for name / description / user-invocable. */
function parseFrontmatter(text) {
    // Strip an optional UTF-8 BOM and normalize CRLF -> LF so the delimiter search
    // and line regex are consistent across editor encodings and Windows checkouts.
    const src = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
    if (!src.startsWith('---'))
        return { fm: {}, body: text };
    const end = src.indexOf('\n---', 3);
    if (end === -1)
        return { fm: {}, body: text };
    const fmText = src.slice(3, end);
    const body = src.slice(end + 4);
    const fm = {};
    let metaUserInvocable;
    const lines = fmText.split('\n');
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.trim() === 'metadata:') {
            let j = i + 1;
            while (j < lines.length && /^\s/.test(lines[j])) {
                const m = lines[j].match(/user-invocable:\s*"?([^"\n]+)"?/);
                if (m)
                    metaUserInvocable = m[1].trim();
                j++;
            }
            i = j - 1;
            continue;
        }
        const m = line.match(/^([A-Za-z0-9_-]+):[ \t]*(.*)$/);
        if (m) {
            const key = m[1];
            const value = m[2].trim();
            if (BLOCK_SCALAR.test(value)) {
                const block = readBlockScalar(lines, i + 1, value[0]);
                fm[key] = block.value;
                i = block.next - 1;
                continue;
            }
            fm[key] = value.replace(/^["']|["']$/g, '');
        }
    }
    if (metaUserInvocable !== undefined)
        fm['user-invocable'] = metaUserInvocable;
    return { fm, body };
}
/** Recursively collect every parseable SKILL.md, reporting whether the walk was exhaustive. */
async function collect(root, registration, options) {
    const items = [];
    let complete = true;
    async function walk(dir) {
        throwIfAborted(registration, options);
        let entries;
        try {
            entries = await readdir(dir, { withFileTypes: true });
        }
        catch {
            // An unreadable directory means this catalog is a partial view; surface that
            // through the observation instead of pretending discovery succeeded.
            complete = false;
            return;
        }
        for (const e of entries) {
            throwIfAborted(registration, options);
            const p = join(dir, e.name);
            if (e.isDirectory())
                await walk(p);
            else if (e.name === 'SKILL.md') {
                const text = await readFile(p, 'utf8');
                const { fm, body } = parseFrontmatter(text);
                if (fm['name'])
                    items.push({ path: p, fm, body });
            }
        }
    }
    await walk(root);
    return { items, complete };
}
/**
 * One provider instance per registration. The catalog cache lives in this closure
 * rather than at module scope, so an HMR remount or a second registration can never
 * reuse candidates built by a provider whose fiber was already disposed.
 */
function createProvider(control) {
    let cache = null;
    async function build(options) {
        if (cache !== null)
            return cache;
        const registration = control.signal;
        const skills = await collect(SKILLS_ROOT, registration, options);
        const ctf = await collect(CTF_ROOT, registration, options);
        const candidates = [...skills.items, ...ctf.items].map(({ path, fm }) => {
            const userInv = fm['user-invocable'];
            return {
                name: fm['name'],
                description: fm['description'] ?? '',
                invocation: {
                    modelInvocable: true,
                    userInvocable: userInv === undefined ? true : userInv !== 'false',
                },
                provider: PROVIDER_NAME,
                source: 'bundled',
                resourceBase: { kind: 'directory', path: dirname(path) },
                path,
                rank: 0,
                locator: pathToFileURL(path),
            };
        });
        const catalog = { candidates, complete: skills.complete && ctf.complete };
        // Only memoize a trustworthy catalog; a partial walk is retried on the next list().
        if (catalog.complete)
            cache = catalog;
        return catalog;
    }
    return {
        name: PROVIDER_NAME,
        async list(options = {}) {
            throwIfAborted(control.signal, options);
            const catalog = await build(options);
            return { candidates: catalog.candidates, complete: catalog.complete };
        },
        async get(candidate, options = {}) {
            throwIfAborted(control.signal, options);
            const source = candidate.path ?? candidate.locator;
            const text = await readFile(source, 'utf8');
            const { body } = parseFrontmatter(text);
            return {
                name: candidate.name,
                description: candidate.description,
                invocation: candidate.invocation,
                provider: candidate.provider,
                source: candidate.source,
                resourceBase: candidate.resourceBase,
                path: candidate.path,
                content: body,
            };
        },
    };
}
/** Cordis plugin name. */
export const name = 'reverse-skill';
/** Service required by this provider. */
export const inject = ['skills'];
/** Register the bundled reverse-skill provider on `ctx.skills`. */
export function apply(ctx) {
    ctx.skills.registerProvider((control) => createProvider(control));
}
