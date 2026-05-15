import { MirageFactory } from './factory.js'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const benchmarksRoot = process.env.CRDT_BENCHMARKS_ROOT

if (!benchmarksRoot) {
  throw new Error('CRDT_BENCHMARKS_ROOT must point to the checked-out crdt-benchmarks repo')
}

const { runBenchmarks, writeBenchmarkResultsToFile } = await import(
  pathToFileURL(path.join(benchmarksRoot, 'js-lib/index.js')).href
)

const envFilter = process.env.MIRAGE_BENCHMARK_FILTER
  ? new RegExp(process.env.MIRAGE_BENCHMARK_FILTER)
  : null

const isSupportedBenchmark = testName =>
  (envFilter == null || envFilter.test(testName)) &&
  !testName.startsWith('[B4x100') &&
  !testName.match(/Array|Map|numbers/) && (
    testName.includes('text') ||
    testName.includes('Text') ||
    testName.includes('string') ||
    testName.includes('characters') ||
    testName.includes('words') ||
    testName.includes('insert & delete') ||
    testName.includes('editing dataset')
  )

await runBenchmarks(new MirageFactory(), isSupportedBenchmark)
writeBenchmarkResultsToFile(path.join(benchmarksRoot, 'benchmarks/results.json'), testName => true)
