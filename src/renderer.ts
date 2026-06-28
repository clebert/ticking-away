import { useSignal, useSignalEffect } from "@preact/signals";
import { useEffect } from "preact/hooks";
import { useAnimation } from "./animation.tsx";
import { getCanvas, resizeCanvas } from "./canvas.ts";
import { type Config, useConfig, writeConfigJson } from "./config.tsx";
import { getWebAssemblyMemory, getWebAssemblyModule } from "./wasm.ts";

export function useRenderer(): void {
  const { hourSignal, minuteSignal } = useAnimation();
  const { configSignal } = useConfig();
  const resizeTriggerSignal = useSignal(0);

  useEffect(() => {
    const handleResize = () => {
      resizeCanvas();
      resizeTriggerSignal.value += 1;
    };

    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  useSignalEffect(() => {
    void resizeTriggerSignal.value;
    renderToCanvas(hourSignal.value, minuteSignal.value, configSignal.value);
  });
}

function renderToCanvas(hour: number, minute: number, config: Config): void {
  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;

  if (width === 0 || height === 0) return;

  const imageDataPointer = getWebAssemblyModule().render(
    width,
    height,
    hour,
    minute,
    writeConfigJson(config),
  );

  if (imageDataPointer === 0) {
    console.error(
      `Watchface render failed at ${width}×${height} — config rejected or ` +
        `WebAssembly allocation failed. Keeping the previous frame.`,
    );

    return;
  }

  const imageData = new ImageData(
    new Uint8ClampedArray(getWebAssemblyMemory().buffer, imageDataPointer, width * height * 4),
    width,
    height,
  );

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
