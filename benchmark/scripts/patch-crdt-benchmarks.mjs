import fs from 'node:fs'
import path from 'node:path'

const root = process.argv[2]

if (!root) {
  console.error('usage: patch-crdt-benchmarks.mjs <crdt-benchmarks-root>')
  process.exit(1)
}

const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'))
const writeJson = (file, data) => {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`)
}

const addUnique = (array, value) => {
  if (!array.includes(value)) array.push(value)
}

const packageJsonPath = path.join(root, 'package.json')
const packageJson = readJson(packageJsonPath)
addUnique(packageJson.workspaces, 'benchmarks/mirage')
packageJson.scripts.table = 'node bin/render-table.js benchmarks/results.json 6000 yjs ywasm automerge mirage'
writeJson(packageJsonPath, packageJson)

const lockPath = path.join(root, 'package-lock.json')
const lock = readJson(lockPath)
const rootPackage = lock.packages['']
addUnique(rootPackage.workspaces, 'benchmarks/mirage')
lock.packages['benchmarks/mirage'] = {
  name: 'mirage-benchmarks',
  version: '1.0.0',
  license: 'MIT'
}
lock.packages['node_modules/mirage-benchmarks'] = {
  resolved: 'benchmarks/mirage',
  link: true
}
writeJson(lockPath, lock)

const yjsRunPath = path.join(root, 'benchmarks/yjs/run.js')
const yjsRun = fs.readFileSync(yjsRunPath, 'utf8')
fs.writeFileSync(
  yjsRunPath,
  yjsRun.replace(
    "await runBenchmarks(new YjsFactory(), testName => true) // !testName.startsWith('[B4x'))",
    "await runBenchmarks(new YjsFactory(), testName => !testName.startsWith('[B4x100'))"
  )
)
