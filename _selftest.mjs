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
    plugin.apply({
      skills: {
        registerProvider(factory) {
          provider = factory()
        },
      },
    })

    assert.ok(provider, 'plugin must register a skill provider')
    const candidates = await provider.list()
    assert.equal(candidates.length, 86, 'expected 85 bundled skills plus the BOM fixture')
    assert.equal(new Set(candidates.map((candidate) => candidate.name)).size, candidates.length, 'skill names must be unique')

    const bundledCandidates = candidates.filter((candidate) => candidate.name !== fixtureName)
    const bundledDefinitions = await Promise.all(bundledCandidates.map((candidate) => provider.get(candidate)))
    assert.ok(bundledDefinitions.every((definition) => definition.content.trim().length > 0), 'every bundled skill must load non-empty content')

    const fixture = candidates.find((candidate) => candidate.name === fixtureName)
    assert.ok(fixture, 'scanner must discover a BOM-prefixed SKILL.md')
    assert.equal(fixture.invocation.userInvocable, false, 'frontmatter metadata must remain effective')

    const definition = await provider.get(fixture)
    assert.equal(definition.content.trim(), 'BOM fixture content.', 'get() must return body without frontmatter or BOM')

    console.log(`Verified ${candidates.length - 1} bundled skills and BOM-tolerant parsing.`)
  } finally {
    await rm(fixtureDir, { recursive: true, force: true })
  }
}

await main()
