#!/usr/bin/env bash
set -euo pipefail

repo="${CRDT_BENCHMARKS_REPO:-https://github.com/dmonad/crdt-benchmarks.git}"
commit="${CRDT_BENCHMARKS_COMMIT:-796f70250c8c003dfb3a50369d0b2733a760e54d}"
cache_dir="${CRDT_BENCHMARKS_CACHE_DIR:-/work/benchmark/.cache}"
worktree="${cache_dir}/crdt-benchmarks"
mirage_dir="${MIRAGE_BENCHMARK_DIR:-/work/benchmark/mirage}"
workspaces="${BENCHMARK_WORKSPACES:-${BENCHMARK_WORKSPACE:-benchmarks/yjs benchmarks/ywasm benchmarks/automerge benchmarks/mirage}}"

if [ ! -f "${MIRAGE_WASM_PATH:-}" ]; then
  echo "Mirage WASM artifact not found: ${MIRAGE_WASM_PATH:-<unset>}" >&2
  echo "Build it first on the host, for example: cd mirage_zig && zig build wasm -Doptimize=ReleaseFast" >&2
  exit 1
fi

mkdir -p "$cache_dir"

if [ ! -d "${worktree}/.git" ]; then
  git clone "$repo" "$worktree"
else
  git -C "$worktree" remote set-url origin "$repo"
  git -C "$worktree" fetch origin
fi

git -C "$worktree" fetch origin "$commit"
git -C "$worktree" checkout --force "$commit"
git -C "$worktree" reset --hard "$commit"

rm -rf "${worktree}/benchmarks/mirage"
ln -s "$mirage_dir" "${worktree}/benchmarks/mirage"

node /work/benchmark/scripts/patch-crdt-benchmarks.mjs "$worktree"

cd "$worktree"
export CRDT_BENCHMARKS_ROOT="$worktree"

if [ ! -f node_modules/lib0/package.json ] || [ "${FORCE_INSTALL:-0}" = "1" ]; then
  npm ci --ignore-scripts
fi

for workspace in $workspaces; do
  npm run start --workspace "$workspace"
done

npm run table
