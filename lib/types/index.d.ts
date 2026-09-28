/**
 * Complete reverse-skill pack as a DeepSeek Harness Cordis plugin.
 *
 * Data-driven provider: it walks the bundled `skills/` and
 * `CTF-Sandbox-Orchestrator/` trees (recursively, so nested sub-skills such as
 * pentest-tools/src-hunter and reverse-engineering/dsl-vm-reverse are discovered
 * too), exposes every SKILL.md through the `ctx.skills` seam, and serves the full
 * body on demand. No manual candidate list to keep in sync with the source pack.
 *
 * Adapted to the DSH 0.1.7-rc.2 skill seam (`@deepseek-ai/dsh-skill` ^0.1.7-alpha.1):
 *
 *   - `registerProvider` now hands the factory a `SkillProviderControl`.
 *     `control.signal` is the registration's lifecycle signal and is honoured
 *     alongside the per-call `options.signal`; `control.invalidate()` is the
 *     provider-to-registry notification and is deliberately never called, because
 *     this pack's catalog is immutable for the lifetime of a registration.
 *   - `list()` may return a `SkillProviderObservation` instead of a bare array.
 *     That is used to report genuinely partial discovery: if a `readdir` under
 *     either root fails, the observation reports `complete: false` so the registry
 *     never caches a truncated catalog as authoritative.
 *   - `path` moved from `SkillCandidate` / `SkillDefinition` up to `SkillSummary`,
 *     so every emitted summary now carries its absolute instruction-file path.
 *   - `SkillService` was renamed to `SkillRegistry`, and the built-in local provider
 *     package to `dsh-skill-filesystem`. Neither name is referenced here.
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
