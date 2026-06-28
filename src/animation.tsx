import {
  batch,
  type ReadonlySignal,
  type Signal,
  useComputed,
  useSignal,
  useSignalEffect,
} from "@preact/signals";
import { createContext, type JSX } from "preact";
import type { PropsWithChildren } from "preact/compat";
import { useContext } from "preact/hooks";
import { useSettings } from "./settings.tsx";

interface AnimationState {
  hourSignal: Signal<number>;
  minuteSignal: Signal<number>;
  framesPerSecondSignal: ReadonlySignal<number>;
}

const animationContext = createContext<AnimationState | undefined>(undefined);

export function AnimationProvider({ children }: PropsWithChildren): JSX.Element {
  const { settingsSignal } = useSettings();
  const now = new Date();
  const hourSignal = useSignal(now.getHours() % 12);
  const minuteSignal = useSignal(now.getMinutes());
  const frameDurationSignal = useSignal(0);

  const framesPerSecondSignal = useComputed(() => {
    const duration = frameDurationSignal.value;
    return duration > 0 ? Math.round(1000 / duration) : 0;
  });

  useSignalEffect(() => {
    const { mode_live, mode_accelerated, mode_speed } = settingsSignal.value;

    if (!mode_live) {
      const minute = minuteSignal.peek();
      const rounded = Math.round(minute) % 60;

      if (rounded !== minute) {
        minuteSignal.value = rounded;
      }

      frameDurationSignal.value = 0;
      return;
    }

    let animationFrameId: number | undefined;
    let realtimeIntervalId: number | undefined;
    let lastFrameTime = 0;

    if (mode_accelerated) {
      const startTimestamp = performance.now();
      const startMinutes = hourSignal.peek() * 60 + minuteSignal.peek();

      const animate = (timestamp: number) => {
        if (lastFrameTime > 0) {
          frameDurationSignal.value = timestamp - lastFrameTime;
        }

        lastFrameTime = timestamp;

        const elapsedSeconds = (timestamp - startTimestamp) / 1000;
        const totalMinutes = startMinutes + elapsedSeconds * mode_speed;
        const wrappedMinutes = totalMinutes % (12 * 60);
        const newMinute = wrappedMinutes % 60;

        batch(() => {
          hourSignal.value = Math.floor(wrappedMinutes / 60);
          minuteSignal.value = newMinute;
        });

        animationFrameId = requestAnimationFrame(animate);
      };

      animationFrameId = requestAnimationFrame(animate);
    } else {
      const updateTime = () => {
        const timestamp = performance.now();

        if (lastFrameTime > 0) {
          frameDurationSignal.value = timestamp - lastFrameTime;
        }

        lastFrameTime = timestamp;

        const currentTime = new Date();
        const fractionalMinute = currentTime.getMinutes() + currentTime.getSeconds() / 60;

        batch(() => {
          hourSignal.value = currentTime.getHours() % 12;
          minuteSignal.value = fractionalMinute;
        });
      };

      updateTime();
      realtimeIntervalId = window.setInterval(updateTime, 1000);
    }

    return () => {
      if (animationFrameId !== undefined) cancelAnimationFrame(animationFrameId);
      if (realtimeIntervalId !== undefined) clearInterval(realtimeIntervalId);
      frameDurationSignal.value = 0;
    };
  });

  return (
    <animationContext.Provider value={{ hourSignal, minuteSignal, framesPerSecondSignal }}>
      {children}
    </animationContext.Provider>
  );
}

export function useAnimation(): AnimationState {
  const animationState = useContext(animationContext);

  if (animationState === undefined) {
    throw new Error("useAnimation must be used within AnimationProvider");
  }

  return animationState;
}
