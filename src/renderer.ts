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
  // glow.falloff: i32 (offset 32)
  view.setInt32(offset + 32, prism.glowFalloff.value, littleEndian);

  // ray.glow_width: f32 (offset 36)
  view.setFloat32(offset + 36, rays.glowWidth.value / 100.0, littleEndian);
  // ray.falloff: i32 (offset 40)
  view.setInt32(offset + 40, rays.glowFalloff.value, littleEndian);
  // ray.ray_palette: i32 (offset 44)
  view.setInt32(offset + 44, rays.palette.value, littleEndian);
  // ray.gradient_fill: i32 (offset 48)
  view.setInt32(offset + 48, rays.gradientFill.value ? 1 : 0, littleEndian);
  // ray.reverse: i32 (offset 52)
  view.setInt32(offset + 52, rays.reverseSpectrum.value ? 1 : 0, littleEndian);

  // marker.visible: i32 (offset 56)
  view.setInt32(offset + 56, display.markers.value ? 1 : 0, littleEndian);
  // marker.length: f32 (offset 60)
  view.setFloat32(offset + 60, markers.length.value / 100.0, littleEndian);
  // marker.glow_width: f32 (offset 64)
  view.setFloat32(offset + 64, markers.glowWidth.value / 100.0, littleEndian);
  // marker.falloff: i32 (offset 68)
  view.setInt32(offset + 68, markers.glowFalloff.value, littleEndian);

  // grain.intensity: f32 (offset 72)
  const grainIntensity = background.grainDisabled.value ? 0 : background.grainIntensity.value / 100;
  view.setFloat32(offset + 72, grainIntensity, littleEndian);
  // grain.scale: f32 (offset 76)
  view.setFloat32(
    offset + 76,
    display.highDpi.value ? window.devicePixelRatio || 1 : 1,
    littleEndian,
  );
  // grain.threshold: f32 (offset 80)
  view.setFloat32(offset + 80, background.grainBrightnessThreshold.value / 100.0, littleEndian);

  // vignette.enabled: i32 (offset 84)
  view.setInt32(offset + 84, dither.enabled.value ? 0 : 1, littleEndian);
  // vignette.strength: f32 (offset 88)
  view.setFloat32(offset + 88, 0.4, littleEndian);
  // vignette.background: f32 (offset 92)
  view.setFloat32(offset + 92, 35.0 / 255.0, littleEndian);

  // dither.enabled: i32 (offset 96)
  view.setInt32(offset + 96, dither.enabled.value ? 1 : 0, littleEndian);
  // dither.mode: i32 (offset 100)
  view.setInt32(offset + 100, dither.paletteMode.value, littleEndian);
  // dither.strength: f32 (offset 104)
  view.setFloat32(offset + 104, dither.strength.value / 100.0, littleEndian);
  // dither.oklab_error: i32 (offset 108)
  view.setInt32(offset + 108, dither.oklabError.value ? 1 : 0, littleEndian);
  // dither.chroma_weight: f32 (offset 112)
  view.setFloat32(offset + 112, dither.chromaWeight.value / 100.0, littleEndian);

  // bounce_mode: i32 (offset 116)
  view.setInt32(offset + 116, time.bounceMode.value, littleEndian);
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
