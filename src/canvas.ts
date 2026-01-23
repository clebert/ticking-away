import { getHeapBase, getWasmMemory } from "./wasm.ts";

export function getCanvas(): HTMLCanvasElement {
  return document.getElementById("canvas") as HTMLCanvasElement;
}

export function resizeCanvas(pebbleMode: boolean, highDpi: boolean): void {
  const canvas = getCanvas();
  const container = canvas.parentElement as HTMLElement;
  const containerRect = container.getBoundingClientRect();
  const devicePixelRatio = highDpi ? window.devicePixelRatio || 1 : 1;

  if (pebbleMode) {
    canvas.width = 260;
    canvas.height = 260;
    canvas.style.width = `${Math.floor(canvas.width / devicePixelRatio)}px`;
    canvas.style.height = `${Math.floor(canvas.height / devicePixelRatio)}px`;
    canvas.style.position = "absolute";
    canvas.style.top = "50%";
    canvas.style.left = "50%";
    canvas.style.transform = "translate(-50%, -50%)";
  } else {
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

export interface FramebufferPointers {
  floatPtr: number; // Float buffer for linear rendering (width*height*16 bytes)
  uint8Ptr: number; // Output buffer (width*height*4 bytes)
}

export function getFramebufferPointers(
  width: number,
  height: number,
): FramebufferPointers | undefined {
  const wasmMemory = getWasmMemory();
  const heapBase = getHeapBase();

  if (!wasmMemory || heapBase === undefined) {
    return;
  }

  const floatBufferSize = width * height * 16; // 4 floats per pixel
  const uint8BufferSize = width * height * 4; // 4 bytes per pixel
  const requiredBytes = heapBase + floatBufferSize + uint8BufferSize;
  const currentBytes = wasmMemory.buffer.byteLength;

  if (currentBytes < requiredBytes) {
    const pagesToGrow = Math.ceil((requiredBytes - currentBytes) / 65536);

    wasmMemory.grow(pagesToGrow);
  }

  return {
    floatPtr: heapBase,
    uint8Ptr: heapBase + floatBufferSize,
  };
}
