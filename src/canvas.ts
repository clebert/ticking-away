export function getCanvas(): HTMLCanvasElement {
  return document.getElementById("canvas") as HTMLCanvasElement;
}

export function resizeCanvas(): void {
  const canvas = getCanvas();
  const container = canvas.parentElement as HTMLElement;
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
