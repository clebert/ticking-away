export function getCanvas(): HTMLCanvasElement {
  return document.getElementById("canvas") as HTMLCanvasElement;
}

export function resizeCanvas(): void {
  const canvas = getCanvas();
  const container = canvas.parentElement as HTMLElement;
  const containerRect = container.getBoundingClientRect();
  const devicePixelRatio = window.devicePixelRatio || 1;

  const newWidth = Math.max(Math.floor(containerRect.width * devicePixelRatio), 100);
  const newHeight = Math.max(Math.floor(containerRect.height * devicePixelRatio), 100);

  if (canvas.width === newWidth && canvas.height === newHeight) {
    return;
  }

  canvas.width = newWidth;
  canvas.height = newHeight;
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  canvas.style.position = "absolute";
  canvas.style.top = "0";
  canvas.style.left = "0";
  canvas.style.transform = "";
}
