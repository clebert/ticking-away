import { batch } from "@preact/signals-core";
import { mode, time } from "./stores.ts";

let animationFrameId: number | undefined;
let realtimeIntervalId: number | undefined;
let acceleratedStartTimestamp = 0;
let acceleratedStartMinutes = 0;
let lastFrameTime = 0;

export function startAnimation(accelerated: boolean, accelerationFactor: number): void {
  if (animationFrameId !== undefined) {
    cancelAnimationFrame(animationFrameId);

    animationFrameId = undefined;
  }

  if (realtimeIntervalId !== undefined) {
    clearInterval(realtimeIntervalId);

    realtimeIntervalId = undefined;
  }

  mode.frameDuration.value = 0;
  lastFrameTime = 0;

  if (accelerated) {
    startAcceleratedAnimation(accelerationFactor);
  } else {
    startRealtimeAnimation();
  }
}

export function stopAnimation(): void {
  if (animationFrameId !== undefined) {
    cancelAnimationFrame(animationFrameId);

    animationFrameId = undefined;
  }

  if (realtimeIntervalId !== undefined) {
    clearInterval(realtimeIntervalId);

    realtimeIntervalId = undefined;
  }

  mode.frameDuration.value = 0;
}

function startAcceleratedAnimation(accelerationFactor: number): void {
  acceleratedStartTimestamp = performance.now();
  acceleratedStartMinutes = time.hours.peek() * 60 + time.minutes.peek();

  const animate = (now: number) => {
    if (lastFrameTime > 0) {
      mode.frameDuration.value = now - lastFrameTime;
    }

    lastFrameTime = now;

    const elapsedSeconds = (now - acceleratedStartTimestamp) / 1000;
    const totalMinutes = acceleratedStartMinutes + elapsedSeconds * accelerationFactor;
    const wrappedMinutes = totalMinutes % (12 * 60);

    const newHours = Math.floor(wrappedMinutes / 60);
    const newMinutes = wrappedMinutes % 60;
    const newSeconds = (newMinutes % 1) * 60;

    batch(() => {
      time.hours.value = newHours;
      time.minutes.value = newMinutes;
      time.seconds.value = newSeconds;
    });

    animationFrameId = requestAnimationFrame(animate);
  };

  animationFrameId = requestAnimationFrame(animate);
}

function startRealtimeAnimation(): void {
  const updateTime = () => {
    const now = performance.now();

    if (lastFrameTime > 0) {
      mode.frameDuration.value = now - lastFrameTime;
    }

    lastFrameTime = now;

    const currentTime = new Date();
    const fractionalSeconds = currentTime.getSeconds();
    const fractionalMinutes = currentTime.getMinutes() + fractionalSeconds / 60;

    batch(() => {
      time.hours.value = currentTime.getHours() % 12;
      time.minutes.value = fractionalMinutes;
      time.seconds.value = fractionalSeconds;
    });
  };

  // Run immediately, then every second (1 fps to limit CPU usage)
  updateTime();
  realtimeIntervalId = window.setInterval(updateTime, 1000);
}
