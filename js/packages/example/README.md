# Mirage minimal example

This package contains a minimal TypeScript example that creates two Mirage
documents, applies local edits to one replica, encodes the missing update, and
applies it to the second replica.

From the `js` workspace:

```bash
pnpm --filter @mirage/example check
pnpm --filter @mirage/example start
```

The example expects the WebAssembly artifact to exist at
`mirage_zig/zig-out/wasm/mirage.wasm`. Build it from `mirage_zig` when needed:

```bash
zig build wasm -Doptimize=ReleaseFast
```
