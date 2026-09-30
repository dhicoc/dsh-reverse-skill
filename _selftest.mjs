import assert from 'node:assert/strict'
import { mkdir, rm, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const packageRoot = dirname(fileURLToPath(import.meta.url))
const skillsRoot = join(packageRoot, 'skills')

// Two temporary fixtures live under skills/ while the test runs and are removed in the
// finally block. Both exercise frontmatter robustness — the part of the scanner that
// upstream content keeps tripping over:
//   __plugin-smoke-bom   -> UTF-8 BOM + CRLF; must not be silently skipped
//   __plugin-smoke-block -> `description: |` block scalar (issue #4); must be parsed
//                           into real text instead of the literal "|"
const fixtures = [
  {
    name: '__plugin-smoke-bom',
    dir: join(skillsRoot, '__plugin-smoke-bom'),
    content:
      '\uFEFF---\r\nname: __plugin-smoke-bom\r\ndescription: BOM parser smoke fixture\r\nuser-invocable: false\r\n---\r\nBOM fixture content.\r\n',
  },
  {
    name: '__plugin-smoke-block',
    dir: join(skillsRoot, '__plugin-smoke-block'),
    // `user-invocable` deliberately sits *after* the block scalar, so the test also
    // proves the parser resumes correctly once the block ends.
    content:
      '---\nname: __plugin-smoke-block\ndescription: |\n  block scalar line one\n  block scalar line two\nuser-invocable: false\n---\nBlock fixture content.\n',
  },
]

const BUNDLED_SKILLS = 88
const FIXTURES = fixtures.length

async function main() {
  for (const fixture of fixtures) {
    await mkdir(fixture.dir, { recursive: true })
    await writeFile(join(fixture.dir, 'SKILL.md'), fixture.content, 'utf8')
  }

  try {
    const plugin = await import('./lib/index.js')
    let provider
    let invalidated = 0
    const controller = new AbortController()

    plugin.apply({
      skills: {
        registerProvider(factory) {
          // DSH 0.2.0-rc.2 hands the factory a SkillProviderControl
          // ({ signal, invalidate }) instead of calling it with no arguments.
          provider = factory({
            signal: controller.signal,
            invalidate: () => {
              invalidated += 1
            },
          })
        },
      },
    })

    assert.ok(provider, 'plugin must register a skill provider')
    assert.equal(provider.name, 'reverse-skill', 'provider keeps its stable name')

    // list() returns a SkillProviderObservation rather than a bare array.
    const observation = await provider.list()
    assert.ok(observation && Array.isArray(observation.candidates), 'list() must return an observation')
    assert.equal(observation.complete, true, 'bundled discovery must report itself complete')

    const candidates = observation.candidates
    assert.equal(
      candidates.length,
      BUNDLED_SKILLS + FIXTURES,
      `expected ${BUNDLED_SKILLS} bundled skills plus ${FIXTURES} fixtures`,
    )
    assert.equal(
      new Set(candidates.map((candidate) => candidate.name)).size,
      candidates.length,
      'skill names must be unique',
    )
    assert.ok(
      candidates.every((c) => typeof c.path === 'string' && c.path.length > 0),
      'path lives on SkillSummary, so every candidate must carry it',
    )
    assert.ok(candidates.every((c) => c.rank === 0), 'bundled candidates rank 0')
    assert.ok(candidates.every((c) => c.source === 'bundled'), 'bundled candidates declare their source')
    assert.ok(
      candidates.every((c) => c.resourceBase?.kind === 'directory' && typeof c.resourceBase.path === 'string'),
      'every candidate exposes a directory resourceBase',
    )

    // options are optional, but an explicit cancellation must be honoured.
    const aborted = new AbortController()
    aborted.abort(new Error('cancelled by test'))
    await assert.rejects(
      () => provider.list({ signal: aborted.signal }),
      /cancelled by test/,
      'an aborted lookup signal must cancel list()',
    )

    // Every bundled skill must load and must carry a real description: ten upstream
    // SKILL.md files write it as a YAML block scalar (issue #4), which used to surface
    // as the literal "|" and left those skills unroutable by description.
    const fixtureNames = new Set(fixtures.map((f) => f.name))
    const bundled = candidates.filter((c) => !fixtureNames.has(c.name))
    assert.equal(bundled.length, BUNDLED_SKILLS, 'bundled candidate count must match the pack')

    const definitions = await Promise.all(bundled.map((c) => provider.get(c)))
    assert.ok(
      definitions.every((d) => d.content.trim().length > 0),
      'every bundled skill must load non-empty content',
    )
    assert.ok(
      definitions.every((d) => typeof d.path === 'string' && d.path.length > 0),
      'definitions keep the instruction-file path',
    )
    assert.ok(
      bundled.every((c) => c.description.trim() !== '|' && c.description.trim().length > 0),
      'every bundled skill must carry a parsed description (no raw "|" left by a block scalar)',
    )

    // --- fixture assertions ---
    const bom = candidates.find((c) => c.name === '__plugin-smoke-bom')
    assert.ok(bom, 'scanner must discover a BOM-prefixed SKILL.md')
    assert.equal(bom.invocation.userInvocable, false, 'frontmatter metadata must remain effective')
    const bomDefinition = await provider.get(bom)
    assert.equal(
      bomDefinition.content.trim(),
      'BOM fixture content.',
      'get() must return the body without frontmatter or BOM',
    )

    const block = candidates.find((c) => c.name === '__plugin-smoke-block')
    assert.ok(block, 'scanner must discover a block-scalar fixture')
    assert.equal(
      block.description,
      'block scalar line one\nblock scalar line two',
      'a `|` block scalar must be parsed into text, not the literal indicator',
    )
    assert.equal(block.invocation.userInvocable, false, 'keys following a block scalar must still be parsed')
    const blockDefinition = await provider.get(block)
    assert.equal(blockDefinition.content.trim(), 'Block fixture content.', 'block-scalar fixture body must load')

    assert.equal(invalidated, 0, 'the provider must not call control.invalidate(); the catalog is immutable')

    console.log(`Verified ${bundled.length} bundled skills (BOM- and block-scalar tolerant).`)
  } finally {
    for (const fixture of fixtures) {
      await rm(fixture.dir, { recursive: true, force: true })
    }
  }
}

await main()
