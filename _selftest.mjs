import assert from 'node:assert/strict'
import { mkdir, rm, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const packageRoot = dirname(fileURLToPath(import.meta.url))
const fixtureDir = join(packageRoot, 'skills', '__plugin-smoke-bom')
const fixturePath = join(fixtureDir, 'SKILL.md')
const fixtureName = '__plugin-smoke-bom'

async function main() {
  await mkdir(fixtureDir, { recursive: true })
  await writeFile(
    fixturePath,
    '\uFEFF---\r\nname: __plugin-smoke-bom\r\ndescription: BOM parser smoke fixture\r\nuser-invocable: false\r\n---\r\nBOM fixture content.\r\n',
    'utf8',
  )

  try {
    const plugin = await import('./lib/index.js')
    let provider
    let invalidated = 0
    const controller = new AbortController()

    plugin.apply({
      skills: {
        registerProvider(factory) {
          // DSH 0.1.7-rc.2 hands the factory a SkillProviderControl
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

    // list() may now return a SkillProviderObservation rather than a bare array.
    const observation = await provider.list()
    assert.ok(observation && Array.isArray(observation.candidates), 'list() must return an observation')
    assert.equal(observation.complete, true, 'bundled discovery must report itself complete')

    const candidates = observation.candidates
    assert.equal(candidates.length, 88, 'expected 87 bundled skills plus the BOM fixture')
    assert.equal(
      new Set(candidates.map((candidate) => candidate.name)).size,
      candidates.length,
      'skill names must be unique',
    )
    assert.ok(
      candidates.every((c) => typeof c.path === 'string' && c.path.length > 0),
      'path moved onto SkillSummary, so every candidate must carry it',
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

    const bundledCandidates = candidates.filter((candidate) => candidate.name !== fixtureName)
    const bundledDefinitions = await Promise.all(bundledCandidates.map((candidate) => provider.get(candidate)))
    assert.ok(
      bundledDefinitions.every((definition) => definition.content.trim().length > 0),
      'every bundled skill must load non-empty content',
    )
    assert.ok(
      bundledDefinitions.every((definition) => typeof definition.path === 'string' && definition.path.length > 0),
      'definitions keep the instruction-file path',
    )

    const fixture = candidates.find((candidate) => candidate.name === fixtureName)
    assert.ok(fixture, 'scanner must discover a BOM-prefixed SKILL.md')
    assert.equal(fixture.invocation.userInvocable, false, 'frontmatter metadata must remain effective')

    const definition = await provider.get(fixture)
    assert.equal(definition.content.trim(), 'BOM fixture content.', 'get() must return body without frontmatter or BOM')

    assert.equal(invalidated, 0, 'an immutable bundled catalog must not notify registry invalidation')

    console.log(`Verified ${candidates.length - 1} bundled skills and BOM-tolerant parsing.`)
  } finally {
    await rm(fixtureDir, { recursive: true, force: true })
  }
}

await main()
