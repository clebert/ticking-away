export function getCanvas(): HTMLCanvasElement {
  const element = document.getElementById("canvas");

  if (!(element instanceof HTMLCanvasElement)) {
    throw new Error("Canvas element not found");
  }

  return element;
}

export function resizeCanvas(): void {
  const canvas = getCanvas();
  const container = canvas.parentElement;

  if (!(container instanceof HTMLElement)) {
    throw new Error("Canvas container element not found");
  }

  const containerRect = container.getBoundingClientRect();
  const devicePixelRatio = window.devicePixelRatio || 1;

  const width = Math.max(Math.floor(containerRect.width * devicePixelRatio), 100);
  const height = Math.max(Math.floor(containerRect.height * devicePixelRatio), 100);

  if (canvas.width === width && canvas.height === height) {
    return;
  }

  canvas.width = width;
  canvas.height = height;
}
