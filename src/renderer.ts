import { getCanvas, getFramebufferPointers } from "./canvas.ts";
import { getConfig } from "./config.ts";
import {
  background,
  debug,
  display,
  dither,
  markers,
  prism,
  rays,
  renderer,
  time,
} from "./stores.ts";
import { getWasmMemory, getWasmModule } from "./wasm.ts";
import { getZigWasmMemory, getZigWasmModule } from "./zig-wasm.ts";

function renderWithC(): void {
  const wasmModule = getWasmModule();
  const wasmMemory = getWasmMemory();

  if (!wasmModule || !wasmMemory) {
    return;
  }

  const config = getConfig(wasmModule, wasmMemory);
  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;
  const pointers = getFramebufferPointers(width, height);

  if (pointers === undefined) {
    return;
  }

  // Update config from stores
  config.hour = time.hours.value;
  config.minute = time.minutes.value;

  // Prism geometry
  config.prism.size = prism.size.value / 100.0;
  config.prism.rainbowSpread = prism.rainbowSpread.value / 100.0;

  // Prism glow (RGB computed from UI stores: gray and blueTint)
  config.glow.r = Math.max(0, prism.gray.value - prism.blueTint.value);
  config.glow.g = Math.max(0, prism.gray.value - Math.floor(prism.blueTint.value / 2));
  config.glow.b = prism.gray.value;
  config.glow.width = prism.glowWidth.value / 100.0;
  config.glow.intensity = prism.glowIntensity.value / 100.0;
  config.glow.falloff = prism.glowFalloff.value;

  // Rays
  config.ray.glowWidth = rays.glowWidth.value / 100.0;
  config.ray.intensity = rays.glowIntensity.value / 100.0;
  config.ray.falloff = rays.glowFalloff.value;
  config.ray.gradientFill = rays.gradientFill.value;
  config.ray.palette = rays.palette.value;
  config.ray.reverse = rays.reverseSpectrum.value;

  // Markers
  config.marker.visible = display.markers.value;
  config.marker.length = markers.length.value / 100.0;
  config.marker.glowWidth = markers.glowWidth.value / 100.0;
  config.marker.glowIntensity = markers.glowIntensity.value / 100.0;
  config.marker.falloff = markers.glowFalloff.value;

  // Grain
  config.grain.intensity = background.grainDisabled.value
    ? 0
    : background.grainIntensity.value / 100.0;
  config.grain.scale = display.highDpi.value ? window.devicePixelRatio || 1 : 1;
  config.grain.threshold = background.grainBrightnessThreshold.value / 100.0;
  config.grain.prismOnly = background.grainPrismOnly.value;

  // Vignette
  config.vignette.enabled = !dither.enabled.value;
  config.vignette.strength = 0.4;
  config.vignette.background = 35.0 / 255.0;

  // Dithering
  config.dither.enabled = dither.enabled.value;
  config.dither.type = dither.type.value;
  config.dither.mode = dither.paletteMode.value;
  // Error diffusion params
  config.dither.strength = dither.strength.value / 100.0;
  config.dither.algorithm = dither.algorithm.value;
  config.dither.oklabError = dither.oklabError.value;
  // Ordered params
  config.dither.orderedMatrix = dither.orderedMatrix.value;
  config.dither.spread = dither.spread.value / 100.0;
  // Shared
  config.dither.chromaWeight = dither.chromaWeight.value / 100.0;

  wasmModule.render_watchface(pointers.floatPtr, pointers.uint8Ptr, width, height);

  // Update debug signals with values computed by WASM
  debug.entryU.value = config.entryU;
  debug.exitU.value = config.exitU;

  const framebufferArray = new Uint8ClampedArray(
    wasmMemory.buffer,
    pointers.uint8Ptr,
    width * height * 4,
  );

  const imageData = new ImageData(framebufferArray, width, height);

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}

function ensureZigMemory(zigMemory: WebAssembly.Memory, neededBytes: number): boolean {
  const currentBytes = zigMemory.buffer.byteLength;

  if (neededBytes <= currentBytes) {
    return true;
  }

  // Add margin and round up to page boundary
  const targetBytes = neededBytes + 65536;
  const pagesToGrow = Math.ceil((targetBytes - currentBytes) / 65536);
  const result = zigMemory.grow(pagesToGrow);

  return result !== -1;
}

function renderWithZig(): void {
  const zigModule = getZigWasmModule();
  const zigMemory = getZigWasmMemory();

  if (!zigModule || !zigMemory) {
    return;
  }

  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;
  const pixelCount = width * height;

  // Zig Color buffer: 4 floats (16 bytes) per pixel (RGBA for SIMD alignment)
  const floatsPerPixel = 4;
  const bytesPerPixel = floatsPerPixel * 4;
  const requiredSize = pixelCount * bytesPerPixel;
  const heapBase = zigModule.getHeapBase();
  const neededBytes = heapBase + requiredSize;

  // Ensure memory is large enough before rendering
  if (!ensureZigMemory(zigMemory, neededBytes)) {
    return;
  }

  // Color buffer is always at heap base
  const colorBufferPtr = heapBase;

  // Render the test pattern
  zigModule.renderTestPattern(colorBufferPtr, width, height);

  // Convert float RGBA to uint8 RGBA (use fresh buffer reference after potential grow)
  const floatView = new Float32Array(zigMemory.buffer, colorBufferPtr, pixelCount * floatsPerPixel);
  const imageData = new ImageData(width, height);
  const data = imageData.data;

  for (let i = 0; i < pixelCount; i++) {
    const srcIdx = i * floatsPerPixel;
    const dstIdx = i * 4;
    const r = floatView[srcIdx] ?? 0;
    const g = floatView[srcIdx + 1] ?? 0;
    const b = floatView[srcIdx + 2] ?? 0;

    data[dstIdx] = Math.min(255, Math.max(0, Math.round(r * 255)));
    data[dstIdx + 1] = Math.min(255, Math.max(0, Math.round(g * 255)));
    data[dstIdx + 2] = Math.min(255, Math.max(0, Math.round(b * 255)));
    data[dstIdx + 3] = 255;
  }

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}

export function render(): void {
  if (renderer.type.value === 1) {
    renderWithZig();
  } else {
    renderWithC();
  }
}
