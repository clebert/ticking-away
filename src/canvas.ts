export function getCanvas(): HTMLCanvasElement {
  return document.getElementById("canvas") as HTMLCanvasElement;
}

export function resizeCanvas(highDpi: boolean): void {
  const canvas = getCanvas();
  const container = canvas.parentElement as HTMLElement;
  const containerRect = container.getBoundingClientRect();
  const devicePixelRatio = highDpi ? window.devicePixelRatio || 1 : 1;

  canvas.width = Math.max(Math.floor(containerRect.width * devicePixelRatio), 100);
  canvas.height = Math.max(Math.floor(containerRect.height * devicePixelRatio), 100);
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  canvas.style.position = "absolute";
  canvas.style.top = "0";
  canvas.style.left = "0";
  canvas.style.transform = "";
}
