import { getCanvas } from "./canvas.ts";
import { background, display, dither, markers, prism, rays, time } from "./stores.ts";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

function writeConfig(view: DataView, offset: number): void {
  const littleEndian = true;

  // hour: i32 (offset 0)
  view.setInt32(offset + 0, time.hours.value, littleEndian);
  // minute: f32 (offset 4)
  view.setFloat32(offset + 4, time.minutes.value, littleEndian);

  // prism.size: f32 (offset 8)
  view.setFloat32(offset + 8, prism.size.value / 100.0, littleEndian);
  // prism.rainbow_spread: f32 (offset 12)
  view.setFloat32(offset + 12, prism.rainbowSpread.value / 100.0, littleEndian);

  // glow.r: i32 (offset 16)
  view.setInt32(offset + 16, Math.max(0, prism.gray.value - prism.blueTint.value), littleEndian);
  // glow.g: i32 (offset 20)
  view.setInt32(
    offset + 20,
    Math.max(0, prism.gray.value - Math.floor(prism.blueTint.value / 2)),
    littleEndian,
  );
  // glow.b: i32 (offset 24)
  view.setInt32(offset + 24, prism.gray.value, littleEndian);
  // glow.width: f32 (offset 28)
  view.setFloat32(offset + 28, prism.glowWidth.value / 100.0, littleEndian);
  // glow.intensity: f32 (offset 32)
  view.setFloat32(offset + 32, prism.glowIntensity.value / 100.0, littleEndian);
  // glow.falloff: i32 (offset 36)
  view.setInt32(offset + 36, prism.glowFalloff.value, littleEndian);

  // ray.glow_width: f32 (offset 40)
  view.setFloat32(offset + 40, rays.glowWidth.value / 100.0, littleEndian);
  // ray.intensity: f32 (offset 44)
  view.setFloat32(offset + 44, rays.glowIntensity.value / 100.0, littleEndian);
  // ray.falloff: i32 (offset 48)
  view.setInt32(offset + 48, rays.glowFalloff.value, littleEndian);
  // ray.ray_palette: i32 (offset 52)
  view.setInt32(offset + 52, rays.palette.value, littleEndian);
  // ray.gradient_fill: i32 (offset 56)
  view.setInt32(offset + 56, rays.gradientFill.value ? 1 : 0, littleEndian);
  // ray.reverse: i32 (offset 60)
  view.setInt32(offset + 60, rays.reverseSpectrum.value ? 1 : 0, littleEndian);

  // marker.visible: i32 (offset 64)
  view.setInt32(offset + 64, display.markers.value ? 1 : 0, littleEndian);
  // marker.length: f32 (offset 68)
  view.setFloat32(offset + 68, markers.length.value / 100.0, littleEndian);
  // marker.glow_width: f32 (offset 72)
  view.setFloat32(offset + 72, markers.glowWidth.value / 100.0, littleEndian);
  // marker.glow_intensity: f32 (offset 76)
  view.setFloat32(offset + 76, markers.glowIntensity.value / 100.0, littleEndian);
  // marker.falloff: i32 (offset 80)
  view.setInt32(offset + 80, markers.glowFalloff.value, littleEndian);

  // grain.intensity: f32 (offset 84)
  const grainIntensity = background.grainDisabled.value ? 0 : background.grainIntensity.value / 100;
  view.setFloat32(offset + 84, grainIntensity, littleEndian);
  // grain.scale: f32 (offset 88)
  view.setFloat32(
    offset + 88,
    display.highDpi.value ? window.devicePixelRatio || 1 : 1,
    littleEndian,
  );
  // grain.threshold: f32 (offset 92)
  view.setFloat32(offset + 92, background.grainBrightnessThreshold.value / 100.0, littleEndian);
  // grain.prism_only: i32 (offset 96)
  view.setInt32(offset + 96, background.grainPrismOnly.value ? 1 : 0, littleEndian);

  // vignette.enabled: i32 (offset 100)
  view.setInt32(offset + 100, dither.enabled.value ? 0 : 1, littleEndian);
  // vignette.strength: f32 (offset 104)
  view.setFloat32(offset + 104, 0.4, littleEndian);
  // vignette.background: f32 (offset 108)
  view.setFloat32(offset + 108, 35.0 / 255.0, littleEndian);

  // dither.enabled: i32 (offset 112)
  view.setInt32(offset + 112, dither.enabled.value ? 1 : 0, littleEndian);
  // dither.dither_type: i32 (offset 116)
  view.setInt32(offset + 116, dither.type.value, littleEndian);
  // dither.mode: i32 (offset 120)
  view.setInt32(offset + 120, dither.paletteMode.value, littleEndian);
  // dither.strength: f32 (offset 124)
  view.setFloat32(offset + 124, dither.strength.value / 100.0, littleEndian);
  // dither.algorithm: i32 (offset 128)
  view.setInt32(offset + 128, dither.algorithm.value, littleEndian);
  // dither.oklab_error: i32 (offset 132)
  view.setInt32(offset + 132, dither.oklabError.value ? 1 : 0, littleEndian);
  // dither.ordered_matrix: i32 (offset 136)
  view.setInt32(offset + 136, dither.orderedMatrix.value, littleEndian);
  // dither.spread: f32 (offset 140)
  view.setFloat32(offset + 140, dither.spread.value / 100.0, littleEndian);
  // dither.chroma_weight: f32 (offset 144)
  view.setFloat32(offset + 144, dither.chromaWeight.value / 100.0, littleEndian);

  // entry_u: f32 (offset 148) - output, leave as 0
  view.setFloat32(offset + 148, 0, littleEndian);
  // exit_u: f32 (offset 152) - output, leave as 0
  view.setFloat32(offset + 152, 0, littleEndian);
}

export function render(): void {
  const wasmModule = getWasmModule();
  const wasmMemory = getWasmMemory();

  if (!wasmModule || !wasmMemory) {
    return;
  }

  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;

  // Write config to static config buffer
  const configPtr = wasmModule.getConfigBuffer();
  const view = new DataView(wasmMemory.buffer);
  writeConfig(view, configPtr);

  // Render watchface (allocates buffers internally)
  const rgbaPtr = wasmModule.renderWatchfaceWithConfig(width, height, configPtr);

  if (rgbaPtr === 0) {
    return;
  }

  // Create ImageData from RGBA output
  const pixelCount = width * height;
  const framebufferArray = new Uint8ClampedArray(wasmMemory.buffer, rgbaPtr, pixelCount * 4);
  const imageData = new ImageData(framebufferArray, width, height);

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
