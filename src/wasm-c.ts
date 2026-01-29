export interface WasmCModule {
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

let wasmCModule: WasmCModule | undefined;
let wasmCMemory: WebAssembly.Memory | undefined;

export async function initWasmC(): Promise<void> {
  wasmCMemory = new WebAssembly.Memory({
    initial: initialMemoryPages,
    maximum: maximumMemoryPages,
  });

  const response = await fetch("/index-c.wasm");
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, {
    env: { memory: wasmCMemory },
  });

  wasmCModule = result.instance.exports as unknown as WasmCModule;
}

export function getWasmCModule(): WasmCModule | undefined {
  return wasmCModule;
}

export function getWasmCMemory(): WebAssembly.Memory | undefined {
  return wasmCMemory;
}

export function getWasmCHeapBase(): number | undefined {
  return wasmCModule?.get_heap_base();
}
