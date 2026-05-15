import { readFileSync } from 'node:fs'

export const name = 'mirage'

const wasmPath = process.env.MIRAGE_WASM_PATH

if (!wasmPath) {
  throw new Error('MIRAGE_WASM_PATH must point to mirage.wasm')
}

const wasmBytes = readFileSync(wasmPath)
const mirage = await createMirage(wasmBytes)

let clientId = 1

/**
 * @implements {CrdtFactory}
 */
export class MirageFactory {
  /**
   * @param {function(Uint8Array):void} updateHandler
   */
  create (updateHandler) {
    return new MirageCRDT(updateHandler)
  }

  /**
   * @param {function(Uint8Array):void} updateHandler
   * @param {Uint8Array} bin
   * @return {AbstractCrdt}
   */
  load (updateHandler, bin) {
    const crdt = new MirageCRDT(updateHandler)
    crdt.applyUpdate(bin)
    return crdt
  }

  getName () {
    return name
  }
}

/**
 * @implements {AbstractCrdt}
 */
export class MirageCRDT {
  /**
   * @param {function(Uint8Array):void} updateHandler
   */
  constructor (updateHandler) {
    this.doc = mirage.createDocument(clientId++)
    this.updateHandler = updateHandler
    this.txnDepth = 0
    this.txnStateVector = null
  }

  /**
   * @return {Uint8Array|string}
   */
  getEncodedState () {
    return this.doc.encodeUpdate()
  }

  /**
   * @param {Uint8Array} update
   */
  applyUpdate (update) {
    this.doc.applyUpdate(update)
  }

  /**
   * @param {number} index
   * @param {string} text
   */
  insertText (index, text) {
    this.withUpdate(() => this.doc.insert(index, text))
  }

  /**
   * @param {number} index
   * @param {number} len
   */
  deleteText (index, len) {
    this.withUpdate(() => this.doc.delete(index, len))
  }

  /**
   * @return {string}
   */
  getText () {
    return this.doc.toString()
  }

  /**
   * @param {function (AbstractCrdt): void} f
   */
  transact (f) {
    const outermost = this.txnDepth === 0
    if (outermost) {
      this.txnStateVector = this.doc.encodeStateVector()
    }
    this.txnDepth++
    try {
      f(this)
    } finally {
      this.txnDepth--
      if (outermost) {
        const stateVector = this.txnStateVector
        this.txnStateVector = null
        this.emitUpdate(stateVector)
      }
    }
  }

  /**
   * @param {function():void} f
   */
  withUpdate (f) {
    if (this.txnDepth > 0) {
      f()
      return
    }
    const stateVector = this.doc.encodeStateVector()
    f()
    this.emitUpdate(stateVector)
  }

  /**
   * @param {Uint8Array|null} stateVector
   */
  emitUpdate (stateVector) {
    const update = this.doc.encodeUpdate(stateVector)
    if (update.length > 0) {
      this.updateHandler(update)
    }
  }
}

/**
 * @param {BufferSource} bytes
 */
async function createMirage (bytes) {
  const result = await WebAssembly.instantiate(bytes, {})
  const wasm = result.instance.exports
  return {
    /**
     * @param {number|bigint} clientId
     */
    createDocument (clientId) {
      return new MirageDocument(wasm, clientId)
    }
  }
}

class MirageDocument {
  /**
   * @param {WebAssembly.Exports} wasm
   * @param {number|bigint} clientId
   */
  constructor (wasm, clientId) {
    this.wasm = wasm
    this.encoder = new TextEncoder()
    this.decoder = new TextDecoder()

    const outDocPtr = this.alloc(4)
    try {
      this.check(this.wasm.doc_create(BigInt(clientId), outDocPtr))
      this.handle = this.view().getUint32(outDocPtr, true)
    } finally {
      this.wasm.free(outDocPtr, 4)
    }
  }

  /**
   * @param {number} index
   * @param {string} text
   */
  insert (index, text) {
    const textBytes = this.writeString(text)
    try {
      this.check(this.wasm.text_insert(this.handle, BigInt(index), textBytes.ptr, textBytes.len))
    } finally {
      this.wasm.free(textBytes.ptr, textBytes.len)
    }
  }

  /**
   * @param {number} index
   * @param {number} len
   */
  delete (index, len) {
    this.check(this.wasm.text_delete(this.handle, BigInt(index), BigInt(len)))
  }

  toString () {
    const outPtrPtr = this.alloc(4)
    const outLenPtr = this.alloc(4)
    try {
      this.check(this.wasm.text_to_string(this.handle, outPtrPtr, outLenPtr))
      return this.decoder.decode(this.readOwnedBytes(outPtrPtr, outLenPtr))
    } finally {
      this.wasm.free(outPtrPtr, 4)
      this.wasm.free(outLenPtr, 4)
    }
  }

  encodeStateVector () {
    const outPtrPtr = this.alloc(4)
    const outLenPtr = this.alloc(4)
    try {
      this.check(this.wasm.text_encode_state_vector(this.handle, outPtrPtr, outLenPtr))
      return this.readOwnedBytes(outPtrPtr, outLenPtr)
    } finally {
      this.wasm.free(outPtrPtr, 4)
      this.wasm.free(outLenPtr, 4)
    }
  }

  /**
   * @param {Uint8Array|null} stateVector
   */
  encodeUpdate (stateVector = null) {
    const stateBytes = stateVector == null ? null : this.writeBytes(stateVector)
    const outPtrPtr = this.alloc(4)
    const outLenPtr = this.alloc(4)
    try {
      this.check(this.wasm.text_encode_update(this.handle, stateBytes?.ptr ?? 0, stateBytes?.len ?? 0, outPtrPtr, outLenPtr))
      return this.readOwnedBytes(outPtrPtr, outLenPtr)
    } finally {
      if (stateBytes != null) {
        this.wasm.free(stateBytes.ptr, stateBytes.len)
      }
      this.wasm.free(outPtrPtr, 4)
      this.wasm.free(outLenPtr, 4)
    }
  }

  /**
   * @param {Uint8Array} update
   */
  applyUpdate (update) {
    const updateBytes = this.writeBytes(update)
    try {
      this.check(this.wasm.text_apply_update(this.handle, updateBytes.ptr, updateBytes.len))
    } finally {
      this.wasm.free(updateBytes.ptr, updateBytes.len)
    }
  }

  /**
   * @param {string} value
   */
  writeString (value) {
    return this.writeBytes(this.encoder.encode(value))
  }

  /**
   * @param {Uint8Array} bytes
   */
  writeBytes (bytes) {
    const ptr = this.alloc(bytes.byteLength)
    this.memory().set(bytes, ptr)
    return { ptr, len: bytes.byteLength }
  }

  /**
   * @param {number} outPtrPtr
   * @param {number} outLenPtr
   */
  readOwnedBytes (outPtrPtr, outLenPtr) {
    const ptr = this.view().getUint32(outPtrPtr, true)
    const len = this.view().getUint32(outLenPtr, true)
    try {
      return this.memory().slice(ptr, ptr + len)
    } finally {
      this.wasm.free(ptr, len)
    }
  }

  /**
   * @param {number} len
   */
  alloc (len) {
    const ptr = this.wasm.alloc(len)
    if (ptr === 0) {
      throw new Error('Mirage WASM allocation failed')
    }
    return ptr
  }

  memory () {
    return new Uint8Array(this.wasm.memory.buffer)
  }

  view () {
    return new DataView(this.wasm.memory.buffer)
  }

  /**
   * @param {number} code
   */
  check (code) {
    if (code !== 0) {
      throw new Error(`Mirage WASM error: ${code}`)
    }
  }
}
