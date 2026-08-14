/**
 * Complete reverse-skill pack as a DeepSeek Harness Cordis plugin.
 *
 * Data-driven provider: it walks the bundled `skills/` and
 * `CTF-Sandbox-Orchestrator/` trees (recursively, so nested sub-skills such as
 * pentest-tools/src-hunter and reverse-engineering/dsl-vm-reverse are discovered
 * too), exposes every SKILL.md through the `ctx.skills` seam, and serves the full
 * body on demand. No manual candidate list to keep in sync with the source pack.
 *
 * @module @reverse-skill/dsh-reverse-skill
 */

import { readFile, readdir } from 'node:fs/promises'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'
import type { Context } from '@deepseek-ai/cordis'
import type {
  SkillCandidate,
  SkillDefinition,
  SkillProvider,
} from '@deepseek-ai/dsh-skill'

// Repo layout: src/index.ts -> lib/index.js ; skills/ and CTF-Sandbox-Orchestrator/
// sit at the package root, one level above lib/. The URL below (no trailing slash,
// no extra dirname) resolves to the skills/ *directory* itself. Note: do NOT wrap in
// dirname() — `new URL('../skills/', import.meta.url)` already ends in a directory name,
// so dirname() would wrongly strip it and leave the package root (which also contains
// node_modules and would double-count every SKILL.md). This holds for both local dev
// (dsh-reverse-skill/lib) and the published package (node_modules/@reverse-skill/dsh-reverse-skill/lib).
const SKILLS_ROOT = fileURLToPath(new URL('../skills', import.meta.url))
const CTF_ROOT = fileURLToPath(new URL('../CTF-Sandbox-Orchestrator', import.meta.url))

const PROVIDER_NAME = 'reverse-skill'

/** Minimal YAML-frontmatter reader — enough for name / description / user-invocable. */
function parseFrontmatter(text: string): { fm: Record<string, string>; body: string } {
  // Normalize CRLF -> LF so the delimiter search and line regex are consistent
  // across files checked out with Windows line endings.
  const src = text.replace(/\r\n/g, '\n')
  if (!src.startsWith('---')) return { fm: {}, body: text }
  const end = src.indexOf('\n---', 3)
  if (end === -1) return { fm: {}, body: text }
  const fmText = src.slice(3, end)
  const body = src.slice(end + 4)
  const fm: Record<string, string> = {}
  let metaUserInvocable: string | undefined
  const lines = fmText.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (line.trim() === 'metadata:') {
      let j = i + 1
      while (j < lines.length && /^\s/.test(lines[j])) {
        const m = lines[j].match(/user-invocable:\s*"?([^"\n]+)"?/)
        if (m) metaUserInvocable = m[1].trim()
        j++
      }
      i = j - 1
      continue
    }
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/)
    if (m) fm[m[1]] = m[2].trim().replace(/^["']|["']$/g, '')
  }
  if (metaUserInvocable !== undefined) fm['user-invocable'] = metaUserInvocable
  return { fm, body }
}

interface Collected {
  path: string
  fm: Record<string, string>
  body: string
}

async function collect(root: string): Promise<Collected[]> {
  const out: Collected[] = []
  async function walk(dir: string): Promise<void> {
    let entries
    try {
      entries = await readdir(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      const p = join(dir, e.name)
      if (e.isDirectory()) await walk(p)
      else if (e.name === 'SKILL.md') {
        const text = await readFile(p, 'utf8')
        const { fm, body } = parseFrontmatter(text)
        if (fm['name']) out.push({ path: p, fm, body })
      }
    }
  }
  await walk(root)
  return out
}

let CACHE: SkillCandidate[] | null = null

async function buildCandidates(): Promise<SkillCandidate[]> {
  if (CACHE) return CACHE
  const all = [...(await collect(SKILLS_ROOT)), ...(await collect(CTF_ROOT))]
  const cands: SkillCandidate[] = all.map(({ path, fm }) => {
    const userInv = fm['user-invocable']
    const candidate: SkillCandidate = {
      name: fm['name'],
      description: fm['description'] ?? '',
      invocation: {
        modelInvocable: true,
        userInvocable: userInv === undefined ? true : userInv !== 'false',
      },
      provider: PROVIDER_NAME,
      source: 'bundled',
      resourceBase: { kind: 'directory', path: dirname(path) },
      rank: 0,
      locator: pathToFileURL(path),
    } as SkillCandidate
    return candidate
  })
  CACHE = cands
  return cands
}

const provider: SkillProvider = {
  name: PROVIDER_NAME,
  list: () => buildCandidates(),
  async get(candidate): Promise<SkillDefinition> {
    const text = await readFile(candidate.locator as URL, 'utf8')
    const { body } = parseFrontmatter(text)
    return {
      name: candidate.name,
      description: candidate.description,
      invocation: candidate.invocation,
      provider: candidate.provider,
      source: candidate.source,
      resourceBase: candidate.resourceBase,
      content: body,
    } as SkillDefinition
  },
}

/** Cordis plugin name. */
export const name = 'reverse-skill'
/** Service required by this provider. */
export const inject = ['skills']

/** Register the bundled reverse-skill provider on `ctx.skills`. */
export function apply(ctx: Context): void {
  ctx.skills.registerProvider(() => provider)
}
