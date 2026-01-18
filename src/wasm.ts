export interface WasmModule {
  get_heap_base(): number;
  get_config(): number;
  render_watchface(
    floatFramebuffer: number,
    framebuffer: number,
    width: number,
    height: number,
  ): void;
}

const initialMemoryPages = 32;
const maximumMemoryPages = 4096; // 256MB max (float buffer is 4× larger than uint8)

let wasmModule: WasmModule | undefined;
let wasmMemory: WebAssembly.Memory | undefined;

export async function initWasm(): Promise<void> {
  wasmMemory = new WebAssembly.Memory({
    initial: initialMemoryPages,
    maximum: maximumMemoryPages,
  });

  const response = await fetch("/index.wasm");
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, {
    env: { memory: wasmMemory },
  });

  wasmModule = result.instance.exports as unknown as WasmModule;
}

export function getWasmModule(): WasmModule | undefined {
  return wasmModule;
}

export function getWasmMemory(): WebAssembly.Memory | undefined {
  return wasmMemory;
}

export function getHeapBase(): number | undefined {
  return wasmModule?.get_heap_base();
}
