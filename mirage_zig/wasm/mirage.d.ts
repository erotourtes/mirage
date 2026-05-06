export type ClientId = bigint | number;
export type Clock = bigint | number;

export type AttributeValue = string | null;

export interface Attribute {
  key: string;
  value: AttributeValue;
}

export interface DeltaOp {
  insert: string;
  attributes?: Record<string, string>;
}

export type ErrorCode =
  | 0 // ok
  | 1 // out_of_memory
  | 2 // invalid_handle
  | 3 // invalid_input
  | 4; // operation_failed

export interface MirageWasmExports {
  memory: WebAssembly.Memory;

  alloc(len: number): number;
  free(ptr: number, len: number): void;

  doc_create(clientId: bigint, outDocPtr: number): ErrorCode;
  doc_destroy(doc: number): ErrorCode;

  text_len(doc: number, outLenPtr: number): ErrorCode;
  text_insert(doc: number, index: bigint, ptr: number, len: number): ErrorCode;
  text_insert_attr(
    doc: number,
    index: bigint,
    textPtr: number,
    textLen: number,
    keyPtr: number,
    keyLen: number,
    valuePtr: number,
    valueLen: number,
    valueIsNull: 0 | 1,
  ): ErrorCode;
  text_format(
    doc: number,
    index: bigint,
    len: bigint,
    keyPtr: number,
    keyLen: number,
    valuePtr: number,
    valueLen: number,
    valueIsNull: 0 | 1,
  ): ErrorCode;
  text_delete(doc: number, index: bigint, len: bigint): ErrorCode;

  text_to_string(doc: number, outPtrPtr: number, outLenPtr: number): ErrorCode;
  text_encode_state_vector(doc: number, outPtrPtr: number, outLenPtr: number): ErrorCode;
  text_encode_update(
    doc: number,
    statePtr: number,
    stateLen: number,
    outPtrPtr: number,
    outLenPtr: number,
  ): ErrorCode;
  text_apply_update(doc: number, updatePtr: number, updateLen: number): ErrorCode;
}

export interface MirageDocument {
  readonly handle: number;
  readonly length: bigint;

  insert(index: Clock, text: string): void;
  insert(index: Clock, text: string, attribute: Attribute): void;
  format(index: Clock, length: Clock, attribute: Attribute): void;
  delete(index: Clock, length: Clock): void;

  toString(): string;
  encodeStateVector(): Uint8Array;
  encodeUpdate(targetStateVector?: Uint8Array | null): Uint8Array;
  applyUpdate(update: Uint8Array): void;
  destroy(): void;
}

export interface Mirage {
  readonly wasm: MirageWasmExports;
  createDocument(clientId: ClientId): MirageDocument;
}

export function instantiateMirage(
  source: BufferSource | WebAssembly.Module | Promise<Response>,
  imports?: WebAssembly.Imports,
): Promise<Mirage>;
