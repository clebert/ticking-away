export interface ZigWasmModule {
  getHeapBase(): number;
  renderTestPattern(buffer: number, width: number, height: number): void;
  clearBuffer(buffer: number, width: number, height: number): void;
  renderGlowLine(
    buffer: number,
    width: number,
    height: number,
    startX: number,
    startY: number,
    endX: number,
    endY: number,
    glowWidth: number,
    falloff: number,
    r: number,
    g: number,
    b: number,
  ): void;
}

const initialMemoryPages = 32;
const maximumMemoryPages = 4096;

let zigWasmModule: ZigWasmModule | undefined;
let zigWasmMemory: WebAssembly.Memory | undefined;

export async function initZigWasm(): Promise<void> {
  zigWasmMemory = new WebAssembly.Memory({
    initial: initialMemoryPages,
    maximum: maximumMemoryPages,
  });

  const response = await fetch("/zig-renderer.wasm");
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, {
    env: { memory: zigWasmMemory },
  });

  zigWasmModule = result.instance.exports as unknown as ZigWasmModule;
}

export function getZigWasmModule(): ZigWasmModule | undefined {
  return zigWasmModule;
}

export function getZigWasmMemory(): WebAssembly.Memory | undefined {
  return zigWasmMemory;
}

export function getZigHeapBase(): number | undefined {
  return zigWasmModule?.getHeapBase();
}
