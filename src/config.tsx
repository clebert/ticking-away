import { type Signal, useSignal, useSignalEffect } from "@preact/signals";
import { createContext, type JSX } from "preact";
import type { PropsWithChildren } from "preact/compat";
import { useContext, useMemo } from "preact/hooks";
import { z } from "zod/mini";
import defaultConfig from "../lib/config.json";
import { getWebAssemblyMemory, getWebAssemblyModule } from "./wasm.ts";

const configSchema = z.object({
  background_enabled: z.boolean(),
  prism_normalized_size: z.number(),
  prism_glow_normalized_width: z.number(),
  rainbow_normalized_spread: z.number(),
  hand_glow_normalized_width: z.number(),
  rainbow_palette_id: z.enum(["oklch_balanced", "spectral"]),
  ray_style: z.enum(["glow", "sharp"]),
  texture: z.enum(["none", "grain", "dither_pebble", "dither_trmnl"]),
  grain_normalized_deviation: z.number(),
});

export type Config = z.infer<typeof configSchema>;

const typedDefaultConfig: Config = configSchema.parse(defaultConfig);

const storageKey = "config";

function loadConfig(): Config {
  try {
    const item = localStorage.getItem(storageKey);

    if (item) {
      const result = z.partial(configSchema).safeParse(JSON.parse(item));

      if (result.success) {
        return Object.assign({ ...typedDefaultConfig }, result.data);
      }
    }
  } catch {}

  return { ...typedDefaultConfig };
}

function saveConfig(config: Config): void {
  try {
    localStorage.setItem(storageKey, JSON.stringify(config));
  } catch {}
}

const configContext = createContext<Signal<Config> | undefined>(undefined);

export function ConfigProvider({ children }: PropsWithChildren): JSX.Element {
  const configSignal = useSignal<Config>(loadConfig());

  useSignalEffect(() => saveConfig(configSignal.value));

  return <configContext.Provider value={configSignal}>{children}</configContext.Provider>;
}

export function useConfig(): Readonly<{
  configSignal: Signal<Config>;
  updateConfig: <ConfigKey extends keyof Config>(key: ConfigKey, value: Config[ConfigKey]) => void;
}> {
  const configSignal = useContext(configContext);

  if (configSignal === undefined) {
    throw new Error("useConfig must be used within ConfigProvider");
  }

  return useMemo(
    () => ({
      configSignal,

      updateConfig<ConfigKey extends keyof Config>(key: ConfigKey, value: Config[ConfigKey]) {
        configSignal.value = { ...configSignal.value, [key]: value };
      },
    }),
    [configSignal],
  );
}

export function resetConfig(configSignal: Signal<Config>): void {
  configSignal.value = { ...typedDefaultConfig };
}

const encoder = new TextEncoder();

// Source the size from WebAssembly so the overflow guard can't diverge from
// config_json_buffer (bin/wasm/main.zig).
let cachedBufferSize = 0;

function configJsonBufferSize(): number {
  if (cachedBufferSize === 0) {
    cachedBufferSize = getWebAssemblyModule().getConfigJsonBufferSize();
  }

  return cachedBufferSize;
}

// Reference-equality cache so writeConfigJson skips re-stringifying unchanged config each frame.
let cachedConfigJson = "";
let cachedConfig: Config | undefined;

function configToJson(config: Config): string {
  if (config === cachedConfig) return cachedConfigJson;

  cachedConfigJson = JSON.stringify(config);
  cachedConfig = config;
  return cachedConfigJson;
}

let lastWrittenJson = "";
let lastBuffer: ArrayBuffer | undefined;

export function writeConfigJson(config: Config): number {
  const json = configToJson(config);
  const buffer = getWebAssemblyMemory().buffer;

  // Re-write if config changed or WebAssembly memory grew (detaches the old ArrayBuffer).
  if (json === lastWrittenJson && buffer === lastBuffer) {
    return 0;
  }

  const bytes = encoder.encode(json);
  const bufferSize = configJsonBufferSize();

  if (bytes.length > bufferSize) {
    throw new Error(
      `Config JSON exceeds WebAssembly buffer: ${bytes.length} > ${bufferSize} bytes`,
    );
  }

  new Uint8Array(buffer, getWebAssemblyModule().getConfigJsonBufferPointer(), bytes.length).set(
    bytes,
  );

  lastWrittenJson = json;
  lastBuffer = buffer;

  return bytes.length;
}
