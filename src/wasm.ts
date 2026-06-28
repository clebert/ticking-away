type WebAssemblyExportFunction = (...values: number[]) => unknown;

export interface WebAssemblyModule {
  getConfigJsonBufferPointer(): number;

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
// wasm32 ceiling: 65536 pages (4 GiB). `maximum` only reserves address space; pages
// commit lazily as the render arena grows, so an unallocatable frame fails the grow and
// render() returns null.
const maximumMemoryPages = 65536;

let webAssemblyModule: WebAssemblyModule | undefined;
let webAssemblyMemory: WebAssembly.Memory | undefined;

export async function initializeWebAssembly(): Promise<void> {
  webAssemblyMemory = new WebAssembly.Memory({
    initial: initialMemoryPages,
    maximum: maximumMemoryPages,
  });

  const response = await fetch(`${import.meta.env.BASE_URL}index.wasm`);
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, {
    env: { memory: webAssemblyMemory },
  });

  webAssemblyModule = createWebAssemblyModule(result.instance.exports);
}

function createWebAssemblyModule(exports: WebAssembly.Exports): WebAssemblyModule {
  const getConfigJsonBufferPointer = getExportFunction(exports, "getConfigJsonBufferPtr");
  const getConfigJsonBufferSize = getExportFunction(exports, "getConfigJsonBufferSize");
  const render = getExportFunction(exports, "render");

  return {
    getConfigJsonBufferPointer() {
      return numberResult("getConfigJsonBufferPtr", getConfigJsonBufferPointer());
    },

    getConfigJsonBufferSize() {
      return numberResult("getConfigJsonBufferSize", getConfigJsonBufferSize());
    },

    render(width, height, hour, minute, configJsonByteLength) {
      return numberResult("render", render(width, height, hour, minute, configJsonByteLength));
    },
  };
}

function getExportFunction(exports: WebAssembly.Exports, name: string): WebAssemblyExportFunction {
  const value = exports[name];

  if (!isWebAssemblyExportFunction(value)) {
    throw new Error(`Missing WebAssembly export: ${name}`);
  }

  return value;
}

function isWebAssemblyExportFunction(value: unknown): value is WebAssemblyExportFunction {
  return typeof value === "function";
}

function numberResult(name: string, result: unknown): number {
  if (typeof result !== "number") {
    throw new Error(`WebAssembly export ${name} returned ${typeof result}`);
  }

  return result;
}

export function getWebAssemblyModule(): WebAssemblyModule {
  if (!webAssemblyModule) {
    throw new Error("WebAssembly module not initialized: call initializeWebAssembly() first");
  }

  return webAssemblyModule;
}

export function getWebAssemblyMemory(): WebAssembly.Memory {
  if (!webAssemblyMemory) {
    throw new Error("WebAssembly memory not initialized: call initializeWebAssembly() first");
  }

  return webAssemblyMemory;
}
