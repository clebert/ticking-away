import { getCanvas, getFramebufferPointers } from "./canvas.ts";
import { background, display, markers, prism, rays, time } from "./stores.ts";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

export function render(): void {
  const wasmModule = getWasmModule();
  const wasmMemory = getWasmMemory();

  if (!wasmModule || !wasmMemory) {
    return;
  }

  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;
  const pointers = getFramebufferPointers(width, height);

  if (pointers === undefined) {
    return;
  }

  const prismRed = Math.max(0, prism.gray.value - prism.blueTint.value);
  const prismGreen = Math.max(0, prism.gray.value - Math.floor(prism.blueTint.value / 2));
  const prismBlue = prism.gray.value;

  wasmModule.render_watchface(
    pointers.floatPtr,
    pointers.uint8Ptr,
    width,
    height,
    time.hours.value,
    time.minutes.value,
    prism.size.value,
    prism.rainbowSpread.value / 100.0,
    display.markers.value ? 1 : 0,
    prismRed,
    prismGreen,
    prismBlue,
    prism.glowWidth.value / 100.0,
    prism.glowIntensity.value / 100.0,
    prism.glowFalloff.value,
    rays.glowWidth.value / 100.0,
    rays.glowIntensity.value / 100.0,
    rays.glowFalloff.value,
    markers.length.value / 100.0,
    markers.glowWidth.value / 100.0,
    markers.glowIntensity.value / 100.0,
    markers.glowFalloff.value,
    background.grainDisabled.value ? 0 : background.grainIntensity.value / 100.0,
    display.highDpi.value ? window.devicePixelRatio || 1 : 1,
    background.grainPrismOnly.value ? 1 : 0,
    rays.gradientFill.value ? 1 : 0,
    display.pebble.value ? 0 : 1,
    rays.palette.value,
    rays.reverseSpectrum.value ? 1 : 0,
  );

  const framebufferArray = new Uint8ClampedArray(
    wasmMemory.buffer,
    pointers.uint8Ptr,
    width * height * 4,
  );

  const imageData = new ImageData(framebufferArray, width, height);

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
