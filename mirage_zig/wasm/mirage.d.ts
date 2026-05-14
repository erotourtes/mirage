export type WasmPtr = number;
export type WasmSize = number;
export type WasmBool = 0 | 1;
export type MirageDocHandle = number;

export type ErrorCode =
  | 0 // ok
  | 1 // out_of_memory
  | 2 // invalid_handle
  | 3 // invalid_input
  | 4; // operation_failed

export interface MirageWasmExports {
  memory: WebAssembly.Memory;

  /**
   * Allocates `len` bytes in wasm memory and returns a wasm32 pointer.
   * Returns 0 on allocation failure.
   */
  alloc(len: WasmSize): WasmPtr;
  free(ptr: WasmPtr, len: WasmSize): void;

  /**
   * Writes an opaque wasm32 document handle to `outDocPtr`.
   */
  doc_create(clientId: bigint, outDocPtr: WasmPtr): ErrorCode;
  doc_destroy(doc: MirageDocHandle): ErrorCode;

  /**
   * Writes the current logical text length as a little-endian u64 to `outLenPtr`.
   */
  text_len(doc: MirageDocHandle, outLenPtr: WasmPtr): ErrorCode;
  text_current_revision(
    doc: MirageDocHandle,
    outRevisionPtr: WasmPtr,
  ): ErrorCode;
  text_history_len(doc: MirageDocHandle, outRevisionPtr: WasmPtr): ErrorCode;
  text_internal_byte_len(doc: MirageDocHandle, outLenPtr: WasmPtr): ErrorCode;
  text_visible_byte_len(
    doc: MirageDocHandle,
    revision: bigint,
    revisionIsNull: WasmBool,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_insert(
    doc: MirageDocHandle,
    index: bigint,
    ptr: WasmPtr,
    len: WasmSize,
  ): ErrorCode;
  text_insert_attr(
    doc: MirageDocHandle,
    index: bigint,
    textPtr: WasmPtr,
    textLen: WasmSize,
    keyPtr: WasmPtr,
    keyLen: WasmSize,
    valuePtr: WasmPtr,
    valueLen: WasmSize,
    valueIsNull: WasmBool,
  ): ErrorCode;
  text_format(
    doc: MirageDocHandle,
    index: bigint,
    len: bigint,
    keyPtr: WasmPtr,
    keyLen: WasmSize,
    valuePtr: WasmPtr,
    valueLen: WasmSize,
    valueIsNull: WasmBool,
  ): ErrorCode;
  text_delete(doc: MirageDocHandle, index: bigint, len: bigint): ErrorCode;
  text_compact(doc: MirageDocHandle): ErrorCode;

  /**
   * Owned-buffer functions write a wasm32 pointer to `outPtrPtr` and a wasm32
   * `usize` byte length to `outLenPtr`. The caller owns the returned buffer and
   * must release it with `free(ptr, len)`.
   */
  text_to_string(
    doc: MirageDocHandle,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_to_string_revision(
    doc: MirageDocHandle,
    revision: bigint,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_to_delta(
    doc: MirageDocHandle,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_to_delta_revision(
    doc: MirageDocHandle,
    revision: bigint,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_to_delta_range(
    doc: MirageDocHandle,
    start: bigint,
    end: bigint,
    revision: bigint,
    revisionIsNull: WasmBool,
    includeLeadingAttrs: WasmBool,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_encode_state_vector(
    doc: MirageDocHandle,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_encode_update(
    doc: MirageDocHandle,
    statePtr: WasmPtr,
    stateLen: WasmSize,
    outPtrPtr: WasmPtr,
    outLenPtr: WasmPtr,
  ): ErrorCode;
  text_apply_update(
    doc: MirageDocHandle,
    updatePtr: WasmPtr,
    updateLen: WasmSize,
  ): ErrorCode;
}
