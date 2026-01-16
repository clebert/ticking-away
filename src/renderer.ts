import { getCanvas, getFramebufferPointer } from "./canvas.ts";
import { background, display, markers, prism, rays, time } from "./stores.ts";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

let frameCounter = 0;

export function render(): void {
  const wasmModule = getWasmModule();
  const wasmMemory = getWasmMemory();

  if (!wasmModule || !wasmMemory) {
    return;
  }

  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;
  const framebufferPointer = getFramebufferPointer(width, height);

  if (framebufferPointer === undefined) {
    return;
  }

  const prismRed = Math.max(0, prism.gray.value - prism.blueTint.value);
  const prismGreen = Math.max(0, prism.gray.value - Math.floor(prism.blueTint.value / 2));
  const prismBlue = prism.gray.value;

  wasmModule.render_watchface(
    framebufferPointer,
    width,
    height,
    time.hours.value,
    time.minutes.value,
    time.seconds.value,
    prism.size.value,
    prism.rainbowSpread.value / 100.0,
    display.markers.value ? 1 : 0,
    prismRed,
    prismGreen,
    prismBlue,
    display.seconds.value && !display.secondsDisabled.value ? 1 : 0,
    prism.sparkleSize.value / 100.0,
    prism.glowWidth.value / 100.0,
    prism.glowIntensity.value / 100.0,
    prism.glowFalloff.value,
    rays.glowWidth.value / 100.0,
    rays.glowIntensity.value / 100.0,
    rays.glowFalloff.value,
    rays.innerSpectrum.value ? 1 : 0,
    rays.artisticDispersion.value ? 1 : 0,
    markers.length.value / 100.0,
    markers.style.value,
    markers.glowWidth.value / 100.0,
    markers.glowIntensity.value / 100.0,
    markers.glowFalloff.value,
    background.grainDisabled.value ? 0 : background.grainIntensity.value / 100.0,
    background.vignetteDisabled.value ? 0 : background.vignetteIntensity.value / 100.0,
    display.dithering.value !== 0 ? 1 : 0,
    frameCounter++,
    background.grainAnimated.value ? 1 : 0,
  );

  if (display.dithering.value !== 0) {
    wasmModule.dither_framebuffer(framebufferPointer, width, height, display.dithering.value);
  }

  const framebufferArray = new Uint8ClampedArray(
    wasmMemory.buffer,
    framebufferPointer,
    width * height * 4,
  );

  const imageData = new ImageData(framebufferArray, width, height);

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
