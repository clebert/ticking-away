import { getCanvas } from "./canvas.ts";
import { display, dither, effects, prism, rainbow, time } from "./stores.ts";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

function writeConfig(view: DataView, offset: number): void {
  const littleEndian = true;

  view.setInt32(offset + 0, time.hour.value, littleEndian);
  view.setFloat32(offset + 4, time.minute.value, littleEndian);

  view.setFloat32(offset + 8, prism.size.value / 100.0, littleEndian);
  view.setFloat32(offset + 12, rainbow.spread.value / 100.0, littleEndian);
  view.setInt32(offset + 16, Math.max(0, prism.gray.value - prism.blueTint.value), littleEndian);

  view.setInt32(
    offset + 20,
    Math.max(0, prism.gray.value - Math.floor(prism.blueTint.value / 2)),
    littleEndian,
  );

  view.setInt32(offset + 24, prism.gray.value, littleEndian);
  view.setFloat32(offset + 28, prism.glowWidth.value / 100.0, littleEndian);
  view.setInt32(offset + 32, prism.glowFalloff.value, littleEndian);

  view.setFloat32(offset + 36, rainbow.handGlowWidth.value / 100.0, littleEndian);
  view.setInt32(offset + 40, rainbow.handGlowFalloff.value, littleEndian);
  view.setInt32(offset + 44, rainbow.palette.value, littleEndian);

  const grainIntensity = dither.enabled.value ? 0 : effects.grainIntensity.value / 100;

  view.setFloat32(offset + 48, grainIntensity, littleEndian);

  view.setFloat32(
    offset + 52,
    display.highDpi.value ? window.devicePixelRatio || 1 : 1,
    littleEndian,
  );

  view.setInt32(offset + 56, dither.enabled.value ? 1 : 0, littleEndian);
  view.setInt32(offset + 60, dither.paletteId.value, littleEndian);
  view.setFloat32(offset + 64, dither.strength.value / 100.0, littleEndian);
  view.setFloat32(offset + 68, dither.chromaEmphasis.value / 100.0, littleEndian);
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

  const configPtr = wasmModule.getConfigPtr();

  writeConfig(new DataView(wasmMemory.buffer), configPtr);

  const imageDataPtr = wasmModule.render(width, height);

  if (imageDataPtr === 0) {
    return;
  }

  const imageData = new ImageData(
    new Uint8ClampedArray(wasmMemory.buffer, imageDataPtr, width * height * 4),
    width,
    height,
  );

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
