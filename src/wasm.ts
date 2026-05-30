export interface WasmModule {
  getConfigJsonBufferPtr(): number;

  getConfigJsonBufferSize(): number;

  render(
    width: number,
    height: number,
    hour: number,
    minute: number,
    configJsonByteLength: number,
  ): number;
}

const initialMemoryPages = 32;
const maximumMemoryPages = 8192;

let wasmModule: WasmModule | undefined;
let wasmMemory: WebAssembly.Memory | undefined;

export async function initWasm(): Promise<void> {
  wasmMemory = new WebAssembly.Memory({
    initial: initialMemoryPages,
    maximum: maximumMemoryPages,
  });

  const response = await fetch(`${import.meta.env.BASE_URL}index.wasm`);
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, {
    env: { memory: wasmMemory },
  });

  wasmModule = result.instance.exports as unknown as WasmModule;
}

export function getWasmModule(): WasmModule {
  if (!wasmModule) {
    throw new Error("WASM module not initialized: call initWasm() first");
  }

  return wasmModule;
}

export function getWasmMemory(): WebAssembly.Memory {
  if (!wasmMemory) {
    throw new Error("WASM memory not initialized: call initWasm() first");
  }

  return wasmMemory;
}
