import { getWasmMemory } from "./wasm.ts";

export function getCanvas(): HTMLCanvasElement {
  return document.getElementById("canvas") as HTMLCanvasElement;
}

export function resizeCanvas(pebbleMode: boolean): void {
  const canvas = getCanvas();
  const container = canvas.parentElement as HTMLElement;
  const containerRect = container.getBoundingClientRect();

  if (pebbleMode) {
    canvas.width = 260;
    canvas.height = 260;
    canvas.style.width = `${canvas.width}px`;
    canvas.style.height = `${canvas.height}px`;
    canvas.style.position = "absolute";
    canvas.style.top = "50%";
    canvas.style.left = "50%";
    canvas.style.transform = "translate(-50%, -50%)";
  } else {
    const devicePixelRatio = window.devicePixelRatio || 1;

    canvas.width = Math.max(Math.floor(containerRect.width * devicePixelRatio), 100);
    canvas.height = Math.max(Math.floor(containerRect.height * devicePixelRatio), 100);
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    canvas.style.position = "absolute";
    canvas.style.top = "0";
    canvas.style.left = "0";
    canvas.style.transform = "";
  }

  container.style.background = "#232323";
}

export function getFramebufferPointer(width: number, height: number): number | undefined {
  const wasmMemory = getWasmMemory();

  if (!wasmMemory) {
    return;
  }

  const framebufferMemoryOffset = 1048576; // 1 MiB offset (safely above WASM stack)
  const requiredBytes = framebufferMemoryOffset + width * height * 4;
  const currentBytes = wasmMemory.buffer.byteLength;

  if (currentBytes < requiredBytes) {
    const pagesToGrow = Math.ceil((requiredBytes - currentBytes) / 65536);

    wasmMemory.grow(pagesToGrow);
  }

  return framebufferMemoryOffset;
}
