import { getCanvas, getFramebufferPointer } from "./canvas.ts";
import { background, display, prism, rays, time } from "./stores.ts";
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
    display.minimal.value ? 1 : 0,
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
    background.grainIntensity.value / 100.0,
    background.vignetteIntensity.value / 100.0,
  );

  if (display.dithering.value) {
    wasmModule.dither_framebuffer(framebufferPointer, width, height);
  }

  const framebufferArray = new Uint8ClampedArray(
    wasmMemory.buffer,
    framebufferPointer,
    width * height * 4,
  );

  const imageData = new ImageData(framebufferArray, width, height);

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
