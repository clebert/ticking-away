import { getWasmMemory } from "./wasm.ts";

const watchWidth = 260;
const watchHeight = 260;
const framebufferMemoryOffset = 1048576; // 1 MiB offset (safely above WASM stack)

let canvas: HTMLCanvasElement;
let canvasContext: CanvasRenderingContext2D;
let framebufferPointer = 0;

export function initCanvas(): void {
  canvas = document.getElementById("canvas") as HTMLCanvasElement;
  canvasContext = canvas.getContext("2d") as CanvasRenderingContext2D;
}

export function getCanvas(): HTMLCanvasElement {
  return canvas;
}

export function getCanvasContext(): CanvasRenderingContext2D {
  return canvasContext;
}

export function getFramebufferPointer(): number {
  return framebufferPointer;
}

export function resizeCanvas(pebbleMode: boolean): void {
  const container = canvas.parentElement as HTMLElement;
  const containerRect = container.getBoundingClientRect();

  let width: number;
  let height: number;

  if (pebbleMode) {
    width = watchWidth;
    height = watchHeight;

    canvas.style.width = `${watchWidth}px`;
    canvas.style.height = `${watchHeight}px`;
    canvas.style.position = "absolute";
    canvas.style.top = "50%";
    canvas.style.left = "50%";
    canvas.style.transform = "translate(-50%, -50%)";

    container.style.background = "#232323";
  } else {
    const devicePixelRatio = window.devicePixelRatio || 1;

    width = Math.max(Math.floor(containerRect.width * devicePixelRatio), 100);
    height = Math.max(Math.floor(containerRect.height * devicePixelRatio), 100);

    canvas.style.width = "100%";
    canvas.style.height = "100%";
    canvas.style.position = "absolute";
    canvas.style.top = "0";
    canvas.style.left = "0";
    canvas.style.transform = "";

    container.style.background = "#000";
  }

  canvas.width = width;
  canvas.height = height;

  ensureWasmMemoryForFramebuffer(width, height);

  framebufferPointer = framebufferMemoryOffset;
}

function ensureWasmMemoryForFramebuffer(width: number, height: number): void {
  const wasmMemory = getWasmMemory();

  if (!wasmMemory) {
    return;
  }

  const framebufferSize = width * height * 4;
  const requiredBytes = framebufferMemoryOffset + framebufferSize;
  const currentBytes = wasmMemory.buffer.byteLength;

  if (currentBytes < requiredBytes) {
    const pagesToGrow = Math.ceil((requiredBytes - currentBytes) / 65536);
    wasmMemory.grow(pagesToGrow);
  }
}
