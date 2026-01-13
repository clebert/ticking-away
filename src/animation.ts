import { batch } from "@preact/signals-core";
import { time } from "./stores.ts";

let animationFrameId: number | undefined;
let acceleratedStartTimestamp = 0;
let acceleratedStartMinutes = 0;

export function startAnimation(accelerated: boolean, accelerationFactor: number): void {
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
}

function startAcceleratedAnimation(accelerationFactor: number): void {
  acceleratedStartTimestamp = performance.now();
  acceleratedStartMinutes = time.hours.peek() * 60 + time.minutes.peek();

  const animate = () => {
    const elapsedSeconds = (performance.now() - acceleratedStartTimestamp) / 1000;
    const totalMinutes = acceleratedStartMinutes + elapsedSeconds * accelerationFactor;
    const wrappedMinutes = totalMinutes % (12 * 60);

    const newHours = Math.floor(wrappedMinutes / 60);
    const newMinutes = wrappedMinutes % 60;
    const newSeconds = (newMinutes * 60) % 60;

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
  const animate = () => {
    const currentTime = new Date();
    const fractionalSeconds = currentTime.getSeconds() + currentTime.getMilliseconds() / 1000;
    const fractionalMinutes = currentTime.getMinutes() + fractionalSeconds / 60;

    batch(() => {
      time.hours.value = currentTime.getHours() % 12;
      time.minutes.value = fractionalMinutes;
      time.seconds.value = fractionalSeconds;
    });

    animationFrameId = requestAnimationFrame(animate);
  };

  animationFrameId = requestAnimationFrame(animate);
}
