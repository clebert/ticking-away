import { useSignal, useSignalEffect } from "@preact/signals";
import { useEffect } from "preact/hooks";
import { useAnimation } from "./animation.tsx";
import { getCanvas, resizeCanvas } from "./canvas.ts";
import { type Config, useConfig, writeConfigJson } from "./config.tsx";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

export function useRenderer(): void {
  const { $hour, $minute } = useAnimation();
  const { $config } = useConfig();
  const $resizeTrigger = useSignal(0);

  useEffect(() => {
    const handleResize = () => {
      resizeCanvas();
      $resizeTrigger.value++;
    };

    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  useSignalEffect(() => {
    void $resizeTrigger.value;
    renderToCanvas($hour.value, $minute.value, $config.value);
  });
}

function renderToCanvas(hour: number, minute: number, config: Config): void {
  const canvas = getCanvas();
  const width = canvas.width;
  const height = canvas.height;

  if (width === 0 || height === 0) return;

  const imageDataPtr = getWasmModule().render(width, height, hour, minute, writeConfigJson(config));

  if (imageDataPtr === 0) return;

  const imageData = new ImageData(
    new Uint8ClampedArray(getWasmMemory().buffer, imageDataPtr, width * height * 4),
    width,
    height,
  );

  canvas.getContext("2d")?.putImageData(imageData, 0, 0);
}
