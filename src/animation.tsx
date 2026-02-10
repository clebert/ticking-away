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
  $hour: Signal<number>;
  $minute: Signal<number>;
  $second: Signal<number>;
  $fps: ReadonlySignal<number>;
}

const AnimationContext = createContext(undefined as unknown as AnimationState);

export function AnimationProvider({ children }: PropsWithChildren): JSX.Element {
  const { $settings } = useSettings();
  const now = new Date();
  const $hour = useSignal(now.getHours() % 12);
  const $minute = useSignal(now.getMinutes());
  const $second = useSignal(now.getSeconds());
  const $frameDuration = useSignal(0);

  const $fps = useComputed(() => {
    const duration = $frameDuration.value;
    return duration > 0 ? Math.round(1000 / duration) : 0;
  });

  useSignalEffect(() => {
    const { mode_live, mode_accelerated, mode_speed } = $settings.value;

    if (!mode_live) {
      const minute = $minute.peek();
      const rounded = Math.round(minute) % 60;

      if (rounded !== minute) {
        $minute.value = rounded;
      }

      $frameDuration.value = 0;
      return;
    }

    let animationFrameId: number | undefined;
    let realtimeIntervalId: number | undefined;
    let lastFrameTime = 0;

    if (mode_accelerated) {
      const startTimestamp = performance.now();
      const startMinutes = $hour.peek() * 60 + $minute.peek();

      const animate = (timestamp: number) => {
        if (lastFrameTime > 0) {
          $frameDuration.value = timestamp - lastFrameTime;
        }

        lastFrameTime = timestamp;

        const elapsedSeconds = (timestamp - startTimestamp) / 1000;
        const totalMinutes = startMinutes + elapsedSeconds * mode_speed;
        const wrappedMinutes = totalMinutes % (12 * 60);
        const newMinute = wrappedMinutes % 60;

        batch(() => {
          $hour.value = Math.floor(wrappedMinutes / 60);
          $minute.value = newMinute;
          $second.value = (newMinute % 1) * 60;
        });

        animationFrameId = requestAnimationFrame(animate);
      };

      animationFrameId = requestAnimationFrame(animate);
    } else {
      const updateTime = () => {
        const timestamp = performance.now();

        if (lastFrameTime > 0) {
          $frameDuration.value = timestamp - lastFrameTime;
        }

        lastFrameTime = timestamp;

        const currentTime = new Date();
        const fractionalSecond = currentTime.getSeconds();
        const fractionalMinute = currentTime.getMinutes() + fractionalSecond / 60;

        batch(() => {
          $hour.value = currentTime.getHours() % 12;
          $minute.value = fractionalMinute;
          $second.value = fractionalSecond;
        });
      };

      updateTime();
      realtimeIntervalId = window.setInterval(updateTime, 1000);
    }

    return () => {
      if (animationFrameId !== undefined) cancelAnimationFrame(animationFrameId);
      if (realtimeIntervalId !== undefined) clearInterval(realtimeIntervalId);
      $frameDuration.value = 0;
    };
  });

  return (
    <AnimationContext.Provider value={{ $hour, $minute, $second, $fps }}>
      {children}
    </AnimationContext.Provider>
  );
}

export function useAnimation(): AnimationState {
  return useContext(AnimationContext);
}
