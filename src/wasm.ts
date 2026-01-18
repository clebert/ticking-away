export interface WasmModule {
  render_watchface(
    floatFramebuffer: number, // Float buffer for linear rendering (width*height*16 bytes)
    framebuffer: number, // Output buffer (width*height*4 bytes)
    width: number,
    height: number,
    hour: number,
    minute: number,
    prism_size_percent: number,
    rainbow_spread: number,
    show_markers: number,
    prism_red: number,
    prism_green: number,
    prism_blue: number,
    glow_width_percent: number,
    glow_intensity: number,
    glow_falloff: number,
    ray_glow_width_percent: number,
    ray_glow_intensity: number,
    ray_glow_falloff: number,
    marker_length_percent: number,
    marker_glow_width_percent: number,
    marker_glow_intensity: number,
    marker_glow_falloff: number,
    grain_intensity: number,
    grain_scale: number,
    grain_prism_only: number,
    gradient_fill: number,
    vignette: number,
    palette: number, // 0=OkLCH Balanced, 1=Saturated, 2=Spectral, 3=Neon, 4=Muted
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
