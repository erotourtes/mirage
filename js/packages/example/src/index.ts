import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { instantiateMirage } from "@mirage/wasm";

const wasmPath = fileURLToPath(
  new URL("../../../../mirage_zig/zig-out/wasm/mirage.wasm", import.meta.url),
);

async function main(): Promise<void> {
  const wasmBytes = await readFile(wasmPath);
  const mirage = await instantiateMirage(wasmBytes);

  const a = mirage.createDocument(1);
  const b = mirage.createDocument(2);

  try {
    a.insert(0, "Hello");
    a.insert(5, " world", { key: "bold", value: "true" });

    const bState = b.encodeStateVector();
    const update = a.encodeUpdate(bState);

    b.applyUpdate(update);

    console.log(b.toString());
    console.log(JSON.stringify(b.toDelta(), null, 2));
  } finally {
    a.destroy();
    b.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
