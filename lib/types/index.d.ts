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
import type { Context } from '@deepseek-ai/cordis';
/** Cordis plugin name. */
export declare const name = "reverse-skill";
/** Service required by this provider. */
export declare const inject: string[];
/** Register the bundled reverse-skill provider on `ctx.skills`. */
export declare function apply(ctx: Context): void;
