import { getCanvas, getFramebufferPointers } from "./canvas.ts";
import { getConfig } from "./config.ts";
import { background, display, markers, prism, rays, time } from "./stores.ts";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

export function render(): void {
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

  config.prismSizePercent = prism.size.value;
  config.rainbowSpread = prism.rainbowSpread.value / 100.0;
  config.prismR = Math.max(0, prism.gray.value - prism.blueTint.value);
  config.prismG = Math.max(0, prism.gray.value - Math.floor(prism.blueTint.value / 2));
  config.prismB = prism.gray.value;
  config.glowWidthPercent = prism.glowWidth.value / 100.0;
  config.glowIntensity = prism.glowIntensity.value / 100.0;
  config.glowFalloff = prism.glowFalloff.value;

  config.rayGlowWidthPercent = rays.glowWidth.value / 100.0;
  config.rayGlowIntensity = rays.glowIntensity.value / 100.0;
  config.rayGlowFalloff = rays.glowFalloff.value;
  config.gradientFill = rays.gradientFill.value;
  config.palette = rays.palette.value;
  config.reverseSpectrum = rays.reverseSpectrum.value;
  config.entryVertexProximity = rays.entryVertexProximity.value / 100.0;
  config.exitVertexProximity = rays.exitVertexProximity.value / 100.0;
  config.simpleBounce = rays.simpleBounce.value;
  config.hideRaysUnderGradient = rays.hideRaysUnderGradient.value;

  config.showMarkers = display.markers.value;
  config.markerLengthPercent = markers.length.value / 100.0;
  config.markerGlowWidthPercent = markers.glowWidth.value / 100.0;
  config.markerGlowIntensity = markers.glowIntensity.value / 100.0;
  config.markerGlowFalloff = markers.glowFalloff.value;

  config.grainIntensity = background.grainDisabled.value
    ? 0
    : background.grainIntensity.value / 100.0;

  config.grainScale = display.highDpi.value ? window.devicePixelRatio || 1 : 1;
  config.grainPrismOnly = background.grainPrismOnly.value;
  config.grainBrightnessThreshold = background.grainBrightnessThreshold.value / 100.0;
  config.vignette = !display.pebble.value;

  wasmModule.render_watchface(pointers.floatPtr, pointers.uint8Ptr, width, height);

  const framebufferArray = new Uint8ClampedArray(
    wasmMemory.buffer,
    pointers.uint8Ptr,
    width * height * 4,
  );

  const imageData = new ImageData(framebufferArray, width, height);

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
