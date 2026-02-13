import { type Signal, useSignal, useSignalEffect } from "@preact/signals";
import { createContext, type JSX } from "preact";
import type { PropsWithChildren } from "preact/compat";
import { useContext, useMemo } from "preact/hooks";
import { z } from "zod/mini";
import defaultConfig from "../lib/config.json";
import { getWasmMemory, getWasmModule } from "./wasm.ts";

const ConfigSchema = z.object({
  background_enabled: z.boolean(),
  prism_normalized_size: z.number(),
  prism_glow_linear_green: z.number(),
  prism_glow_normalized_width: z.number(),
  prism_glow_falloff: z.enum(["linear", "quadratic", "cubic", "exponential"]),
  rainbow_normalized_spread: z.number(),
  hand_glow_normalized_width: z.number(),
  hand_glow_falloff: z.enum(["linear", "quadratic", "cubic", "exponential"]),
  hand_length_falloff: z.enum(["linear", "quadratic", "cubic", "exponential"]),
  rainbow_palette_id: z.enum(["oklch_balanced", "spectral", "spectra6"]),
  grain_enabled: z.boolean(),
  grain_normalized_deviation: z.number(),
  dither_enabled: z.boolean(),
  dither_palette_id: z.enum(["ideal", "spectra6_inky", "spectra6_epdopt", "spectra6_trmnl"]),
  dither_normalized_strength: z.number(),
  dither_normalized_chroma_emphasis: z.number(),
});

export type Config = z.infer<typeof ConfigSchema>;

const typedDefaultConfig: Config = ConfigSchema.parse(defaultConfig);

function loadConfig(): Config {
  try {
    const item = localStorage.getItem("config");

    if (item) {
      const result = z.partial(ConfigSchema).safeParse(JSON.parse(item));

      if (result.success) {
        // Spread of full defaults + validated partial always produces a complete Config
        return Object.assign({ ...typedDefaultConfig }, result.data);
      }
    }
  } catch {
    // Ignore localStorage errors
  }

  return typedDefaultConfig;
}

function saveConfig(config: Config): void {
  try {
    localStorage.setItem("config", JSON.stringify(config));
  } catch {
    // Ignore localStorage errors
  }
}

// --- Context & Provider ---

const ConfigContext = createContext(undefined as unknown as Signal<Config>);

export function ConfigProvider({ children }: PropsWithChildren): JSX.Element {
  const $config = useSignal<Config>(loadConfig());

  useSignalEffect(() => saveConfig($config.value));

  return <ConfigContext.Provider value={$config}>{children}</ConfigContext.Provider>;
}

export function useConfig(): Readonly<{
  $config: Signal<Config>;
  updateConfig: <K extends keyof Config>(key: K, value: Config[K]) => void;
}> {
  const $config = useContext(ConfigContext);

  return useMemo(
    () => ({
      $config,

      updateConfig<K extends keyof Config>(key: K, value: Config[K]) {
        $config.value = { ...$config.value, [key]: value };
      },
    }),
    [$config],
  );
}

export function resetConfig($config: Signal<Config>): void {
  $config.value = { ...typedDefaultConfig };
}

// --- WASM config serialization ---

const encoder = new TextEncoder();
const configJsonBufferSize = 1024;

// Cached alongside the config signal so writeConfigJson can do a cheap reference
// check instead of re-stringifying on every render frame.
let cachedConfigJson = "";
let cachedConfig: Config | undefined;

export function configToJson(config: Config): string {
  if (config === cachedConfig) return cachedConfigJson;

  cachedConfigJson = JSON.stringify(config);
  cachedConfig = config;
  return cachedConfigJson;
}

let lastWrittenJson = "";
let lastBuffer: ArrayBuffer | undefined;

export function writeConfigJson(config: Config): number {
  const json = configToJson(config);
  const buffer = getWasmMemory().buffer;

  // Re-write if config changed or WASM memory grew (detaches the old ArrayBuffer)
  if (json === lastWrittenJson && buffer === lastBuffer) {
    return 0;
  }

  const bytes = encoder.encode(json);

  if (bytes.length > configJsonBufferSize) {
    throw new Error(
      `Config JSON exceeds WASM buffer: ${bytes.length} > ${configJsonBufferSize} bytes`,
    );
  }

  new Uint8Array(buffer, getWasmModule().getConfigJsonBufferPtr(), bytes.length).set(bytes);

  lastWrittenJson = json;
  lastBuffer = buffer;

  return bytes.length;
}
