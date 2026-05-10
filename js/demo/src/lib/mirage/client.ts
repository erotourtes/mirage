import { loadMirage as loadMiragePackage } from "@mirage/wasm";
import type { Mirage, MirageDocument } from "@mirage/wasm";

let miragePromise: Promise<Mirage> | null = null;

export function loadMirage(): Promise<Mirage> {
  miragePromise ??= loadMiragePackage();
  return miragePromise;
}

export async function createDemoDocument(
  initialText = "Mirage is running in WebAssembly.",
): Promise<MirageDocument> {
  const mirage = await loadMirage();
  const doc = mirage.createDocument(1);
  doc.insert(0, initialText);
  return doc;
}
