Check `zig build --help` for steps you can run. Most valuable are

```bash
zig build test                         # Run tests
zig build wasm -Doptimize=ReleaseFast  # Build the WebAssembly artifact
```

To debug pointers download the [pretty printers script](https://codeberg.org/ziglang/zig/src/branch/0.16.x/tools/lldb_pretty_printers.py) and put it in near this README.md file.

[Video tutorial](https://www.youtube.com/watch?v=HNPatMGBXa4)
