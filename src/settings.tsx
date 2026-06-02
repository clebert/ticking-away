import { type Signal, useSignal, useSignalEffect } from "@preact/signals";
import { createContext, type JSX } from "preact";
import type { PropsWithChildren } from "preact/compat";
import { useContext, useMemo } from "preact/hooks";
import { z } from "zod/mini";

const SettingsSchema = z.object({
  mode_live: z.boolean(),
  mode_accelerated: z.boolean(),
  mode_speed: z.number(),
});

export type Settings = z.infer<typeof SettingsSchema>;

function createDefaultSettings(): Settings {
  return {
    mode_live: true,
    mode_accelerated: false,
    mode_speed: 1,
  };
}

const SettingsContext = createContext(undefined as unknown as Signal<Settings>);

export function SettingsProvider({ children }: PropsWithChildren): JSX.Element {
  const $settings = useSignal<Settings>(loadSettings());

  useSignalEffect(() => saveSettings($settings.value));

  return <SettingsContext.Provider value={$settings}>{children}</SettingsContext.Provider>;
}

export function useSettings(): Readonly<{
  $settings: Signal<Settings>;
  updateSettings: <K extends keyof Settings>(key: K, value: Settings[K]) => void;
}> {
  const $settings = useContext(SettingsContext);

  return useMemo(
    () => ({
      $settings,

      updateSettings<K extends keyof Settings>(key: K, value: Settings[K]) {
        $settings.value = { ...$settings.value, [key]: value };
      },
    }),
    [$settings],
  );
}

export function resetSettings($settings: Signal<Settings>): void {
  $settings.value = createDefaultSettings();
}

const storageKey = "settings";

function loadSettings(): Settings {
  const defaults = createDefaultSettings();

  try {
    const item = localStorage.getItem(storageKey);

    if (item) {
      const result = z.partial(SettingsSchema).safeParse(JSON.parse(item));

      if (result.success) {
        return Object.assign({ ...defaults }, result.data);
      }
    }
  } catch {}

  return defaults;
}

function saveSettings(settings: Settings): void {
  try {
    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {}
}
