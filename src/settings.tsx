import { type Signal, useSignal, useSignalEffect } from "@preact/signals";
import { createContext, type JSX } from "preact";
import type { PropsWithChildren } from "preact/compat";
import { useContext, useMemo } from "preact/hooks";
import { z } from "zod/mini";

const settingsSchema = z.object({
  mode_live: z.boolean(),
  mode_accelerated: z.boolean(),
  mode_speed: z.number(),
});

export type Settings = z.infer<typeof settingsSchema>;

function createDefaultSettings(): Settings {
  return {
    mode_live: true,
    mode_accelerated: false,
    mode_speed: 1,
  };
}

const settingsContext = createContext<Signal<Settings> | undefined>(undefined);

export function SettingsProvider({ children }: PropsWithChildren): JSX.Element {
  const settingsSignal = useSignal<Settings>(loadSettings());

  useSignalEffect(() => saveSettings(settingsSignal.value));

  return <settingsContext.Provider value={settingsSignal}>{children}</settingsContext.Provider>;
}

export function useSettings(): Readonly<{
  settingsSignal: Signal<Settings>;
  updateSettings: <SettingsKey extends keyof Settings>(
    key: SettingsKey,
    value: Settings[SettingsKey],
  ) => void;
}> {
  const settingsSignal = useContext(settingsContext);

  if (settingsSignal === undefined) {
    throw new Error("useSettings must be used within SettingsProvider");
  }

  return useMemo(
    () => ({
      settingsSignal,

      updateSettings<SettingsKey extends keyof Settings>(
        key: SettingsKey,
        value: Settings[SettingsKey],
      ) {
        settingsSignal.value = { ...settingsSignal.value, [key]: value };
      },
    }),
    [settingsSignal],
  );
}

export function resetSettings(settingsSignal: Signal<Settings>): void {
  settingsSignal.value = createDefaultSettings();
}

const storageKey = "settings";

function loadSettings(): Settings {
  const defaults = createDefaultSettings();

  try {
    const item = localStorage.getItem(storageKey);

    if (item) {
      const result = z.partial(settingsSchema).safeParse(JSON.parse(item));

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
