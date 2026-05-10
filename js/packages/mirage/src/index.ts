import type {
  ErrorCode,
  MirageDocHandle,
  MirageWasmExports,
} from "../wasm/mirage.d.ts";

export type { ErrorCode, MirageDocHandle, MirageWasmExports };

export type ClientId = bigint | number;
export type Clock = bigint | number;
export type Revision = bigint | number;

export type AttributeValue = string | null;

export interface Attribute {
  key: string;
  value: AttributeValue;
}

export interface DeltaOp {
  insert: string;
  attributes?: Record<string, string>;
}

export interface MirageDocument {
  readonly handle: MirageDocHandle;
  readonly length: bigint;
  readonly currentRevision: bigint;
  readonly historyLength: bigint;

  insert(index: Clock, text: string): void;
  insert(index: Clock, text: string, attribute: Attribute): void;
  format(index: Clock, length: Clock, attribute: Attribute): void;
  delete(index: Clock, length: Clock): void;
  compact(): void;

  toString(revision?: Revision | null): string;
  encodeStateVector(): Uint8Array;
  encodeUpdate(targetStateVector?: Uint8Array | null): Uint8Array;
  applyUpdate(update: Uint8Array): void;
  destroy(): void;
}

export interface Mirage {
  readonly wasm: MirageWasmExports;
  createDocument(clientId: ClientId): MirageDocument;
}

export const MIRAGE_WASM_URL = new URL("../wasm/mirage.wasm", import.meta.url)
  .href;

const errorMessages: Record<ErrorCode, string> = {
  0: "ok",
  1: "out of memory",
  2: "invalid handle",
  3: "invalid input",
  4: "operation failed",
};

export function loadMirage(
  source: BufferSource | WebAssembly.Module | Promise<Response> = fetch(
    MIRAGE_WASM_URL,
  ),
  imports?: WebAssembly.Imports,
): Promise<Mirage> {
  return instantiateMirage(source, imports);
}

export async function instantiateMirage(
  source: BufferSource | WebAssembly.Module | Promise<Response>,
  imports: WebAssembly.Imports = {},
): Promise<Mirage> {
  const wasm = await instantiateExports(source, imports);

  return {
    wasm,
    createDocument(clientId: ClientId) {
      return new WasmDocument(wasm, clientId);
    },
  };
}

async function instantiateExports(
  source: BufferSource | WebAssembly.Module | Promise<Response>,
  imports: WebAssembly.Imports,
): Promise<MirageWasmExports> {
  if (source instanceof WebAssembly.Module) {
    const instance = await WebAssembly.instantiate(source, imports);
    return instance.exports as unknown as MirageWasmExports;
  } else if (source instanceof Promise) {
    const response = await source;
    try {
      const result = await WebAssembly.instantiateStreaming(
        response.clone(),
        imports,
      );
      return result.instance.exports as unknown as MirageWasmExports;
    } catch {
      const bytes = await response.arrayBuffer();
      const result = await WebAssembly.instantiate(bytes, imports);
      return result.instance.exports as unknown as MirageWasmExports;
    }
  }

  const result = await WebAssembly.instantiate(source, imports);
  return result.instance.exports as unknown as MirageWasmExports;
}

class WasmDocument implements MirageDocument {
  readonly handle: number;

  private wasm: MirageWasmExports;
  private destroyed = false;
  private encoder = new TextEncoder();
  private decoder = new TextDecoder();

  constructor(wasm: MirageWasmExports, clientId: ClientId) {
    this.wasm = wasm;
    const outDocPtr = this.allocScratch(4);

    try {
      this.check(wasm.doc_create(BigInt(clientId), outDocPtr));
      this.handle = this.view().getUint32(outDocPtr, true);
    } finally {
      wasm.free(outDocPtr, 4);
    }
  }

  get length(): bigint {
    return this.readU64((outPtr) => this.wasm.text_len(this.handle, outPtr));
  }

  get currentRevision(): bigint {
    return this.readU64((outPtr) =>
      this.wasm.text_current_revision(this.handle, outPtr),
    );
  }

  get historyLength(): bigint {
    return this.readU64((outPtr) =>
      this.wasm.text_history_len(this.handle, outPtr),
    );
  }

  insert(index: Clock, text: string, attribute?: Attribute): void {
    this.assertAlive();

    if (!attribute) {
      const textBytes = this.writeBytes(text);

      try {
        this.check(
          this.wasm.text_insert(
            this.handle,
            BigInt(index),
            textBytes.ptr,
            textBytes.len,
          ),
        );
      } finally {
        this.wasm.free(textBytes.ptr, textBytes.len);
      }

      return;
    }

    const textBytes = this.writeBytes(text);
    const keyBytes = this.writeBytes(attribute.key);
    const valueBytes =
      attribute.value === null ? null : this.writeBytes(attribute.value);

    try {
      this.check(
        this.wasm.text_insert_attr(
          this.handle,
          BigInt(index),
          textBytes.ptr,
          textBytes.len,
          keyBytes.ptr,
          keyBytes.len,
          valueBytes?.ptr ?? 0,
          valueBytes?.len ?? 0,
          attribute.value === null ? 1 : 0,
        ),
      );
    } finally {
      this.wasm.free(textBytes.ptr, textBytes.len);
      this.wasm.free(keyBytes.ptr, keyBytes.len);
      if (valueBytes) this.wasm.free(valueBytes.ptr, valueBytes.len);
    }
  }

  format(index: Clock, length: Clock, attribute: Attribute): void {
    this.assertAlive();
    const keyBytes = this.writeBytes(attribute.key);
    const valueBytes =
      attribute.value === null ? null : this.writeBytes(attribute.value);

    try {
      this.check(
        this.wasm.text_format(
          this.handle,
          BigInt(index),
          BigInt(length),
          keyBytes.ptr,
          keyBytes.len,
          valueBytes?.ptr ?? 0,
          valueBytes?.len ?? 0,
          attribute.value === null ? 1 : 0,
        ),
      );
    } finally {
      this.wasm.free(keyBytes.ptr, keyBytes.len);
      if (valueBytes) this.wasm.free(valueBytes.ptr, valueBytes.len);
    }
  }

  delete(index: Clock, length: Clock): void {
    this.assertAlive();
    this.check(
      this.wasm.text_delete(this.handle, BigInt(index), BigInt(length)),
    );
  }

  compact(): void {
    this.assertAlive();
    this.check(this.wasm.text_compact(this.handle));
  }

  toString(revision?: Revision | null): string {
    this.assertAlive();
    const outPtrPtr = this.allocScratch(4);
    const outLenPtr = this.allocScratch(4);

    try {
      const code =
        revision === null || revision === undefined
          ? this.wasm.text_to_string(this.handle, outPtrPtr, outLenPtr)
          : this.wasm.text_to_string_revision(
              this.handle,
              BigInt(revision),
              outPtrPtr,
              outLenPtr,
            );

      this.check(code);
      return this.readOwnedString(outPtrPtr, outLenPtr);
    } finally {
      this.wasm.free(outPtrPtr, 4);
      this.wasm.free(outLenPtr, 4);
    }
  }

  encodeStateVector(): Uint8Array {
    this.assertAlive();
    const outPtrPtr = this.allocScratch(4);
    const outLenPtr = this.allocScratch(4);

    try {
      this.check(
        this.wasm.text_encode_state_vector(this.handle, outPtrPtr, outLenPtr),
      );
      return this.readOwnedBytes(outPtrPtr, outLenPtr);
    } finally {
      this.wasm.free(outPtrPtr, 4);
      this.wasm.free(outLenPtr, 4);
    }
  }

  encodeUpdate(targetStateVector?: Uint8Array | null): Uint8Array {
    this.assertAlive();
    const stateBytes = targetStateVector
      ? this.writeRawBytes(targetStateVector)
      : null;
    const outPtrPtr = this.allocScratch(4);
    const outLenPtr = this.allocScratch(4);

    try {
      this.check(
        this.wasm.text_encode_update(
          this.handle,
          stateBytes?.ptr ?? 0,
          stateBytes?.len ?? 0,
          outPtrPtr,
          outLenPtr,
        ),
      );
      return this.readOwnedBytes(outPtrPtr, outLenPtr);
    } finally {
      if (stateBytes) this.wasm.free(stateBytes.ptr, stateBytes.len);
      this.wasm.free(outPtrPtr, 4);
      this.wasm.free(outLenPtr, 4);
    }
  }

  applyUpdate(update: Uint8Array): void {
    this.assertAlive();
    const updateBytes = this.writeRawBytes(update);

    try {
      this.check(
        this.wasm.text_apply_update(
          this.handle,
          updateBytes.ptr,
          updateBytes.len,
        ),
      );
    } finally {
      this.wasm.free(updateBytes.ptr, updateBytes.len);
    }
  }

  destroy(): void {
    if (this.destroyed) return;
    this.check(this.wasm.doc_destroy(this.handle));
    this.destroyed = true;
  }

  private readU64(read: (outPtr: number) => ErrorCode): bigint {
    this.assertAlive();
    const outPtr = this.allocScratch(8);

    try {
      this.check(read(outPtr));
      return this.view().getBigUint64(outPtr, true);
    } finally {
      this.wasm.free(outPtr, 8);
    }
  }

  private allocScratch(len: number): number {
    const ptr = this.wasm.alloc(len);
    if (ptr === 0) throw new Error("Mirage WASM allocation failed");
    return ptr;
  }

  private writeBytes(value: string): { ptr: number; len: number } {
    return this.writeRawBytes(this.encoder.encode(value));
  }

  private writeRawBytes(bytes: Uint8Array): { ptr: number; len: number } {
    const ptr = this.allocScratch(bytes.byteLength);
    this.memory().set(bytes, ptr);
    return { ptr, len: bytes.byteLength };
  }

  private readOwnedString(outPtrPtr: number, outLenPtr: number): string {
    const bytes = this.readOwnedBytes(outPtrPtr, outLenPtr);
    return this.decoder.decode(bytes);
  }

  private readOwnedBytes(outPtrPtr: number, outLenPtr: number): Uint8Array {
    const ptr = this.view().getUint32(outPtrPtr, true);
    const len = this.view().getUint32(outLenPtr, true);

    try {
      return this.memory().slice(ptr, ptr + len);
    } finally {
      this.wasm.free(ptr, len);
    }
  }

  private memory(): Uint8Array {
    return new Uint8Array(this.wasm.memory.buffer);
  }

  private view(): DataView {
    return new DataView(this.wasm.memory.buffer);
  }

  private check(code: ErrorCode): void {
    if (code !== 0) {
      throw new Error(
        `Mirage WASM error: ${errorMessages[code] ?? `unknown code ${code}`}`,
      );
    }
  }

  private assertAlive(): void {
    if (this.destroyed) throw new Error("Mirage document has been destroyed");
  }
}
