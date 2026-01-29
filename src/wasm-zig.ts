export interface WasmZigModule {
  getConfigBuffer(): number;
  renderWatchfaceWithConfig(width: number, height: number, config: number): number;
}

const initialMemoryPages = 32;
const maximumMemoryPages = 4096;

let wasmZigModule: WasmZigModule | undefined;
let wasmZigMemory: WebAssembly.Memory | undefined;

export async function initWasmZig(): Promise<void> {
  wasmZigMemory = new WebAssembly.Memory({
    initial: initialMemoryPages,
    maximum: maximumMemoryPages,
  });

  const response = await fetch("/index-zig.wasm");
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, {
    env: { memory: wasmZigMemory },
  });

  wasmZigModule = result.instance.exports as unknown as WasmZigModule;
}

export function getWasmZigModule(): WasmZigModule | undefined {
  return wasmZigModule;
}

export function getWasmZigMemory(): WebAssembly.Memory | undefined {
  return wasmZigMemory;
}
