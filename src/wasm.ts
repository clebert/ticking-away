export interface WasmModule {
  render_watchface(
    framebuffer: number,
    width: number,
    height: number,
    hour: number,
    minute: number,
    second: number,
    prism_size_percent: number,
    rainbow_spread: number,
    show_markers: number,
    prism_red: number,
    prism_green: number,
    prism_blue: number,
    show_seconds: number,
    sparkle_size_percent: number,
    glow_width_percent: number,
    glow_intensity: number,
    glow_falloff: number,
    ray_glow_width_percent: number,
    ray_glow_intensity: number,
    ray_glow_falloff: number,
    internal_ray_real_colors: number,
    artistic_dispersion: number,
    grain_intensity: number,
    vignette_intensity: number,
    white_background: number,
    frame: number,
    grain_animated: number,
  ): void;

  dither_framebuffer(framebuffer: number, width: number, height: number, mode: number): void;
}

const initialMemoryPages = 32;
const maximumMemoryPages = 1024;

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
