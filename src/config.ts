import { createStruct, type Struct } from "./struct.ts";
import type { WasmModule } from "./wasm.ts";

export type WatchfaceConfig = Struct<typeof fields>;

let cachedConfig: WatchfaceConfig | undefined;

export function getConfig(wasmModule: WasmModule, wasmMemory: WebAssembly.Memory): WatchfaceConfig {
  if (!cachedConfig) {
    cachedConfig = createStruct(wasmMemory, wasmModule.get_config(), fields);
  }

  return cachedConfig;
}

// Order must match C struct layout in config.h
const fields = {
  // Time
  hour: "int32",
  minute: "float32",

  // Prism
  prismSizePercent: "float32",
  rainbowSpread: "float32",
  prismR: "int32",
  prismG: "int32",
  prismB: "int32",
  glowWidthPercent: "float32",
  glowIntensity: "float32",
  glowFalloff: "int32",

  // Rays
  rayGlowWidthPercent: "float32",
  rayGlowIntensity: "float32",
  rayGlowFalloff: "int32",
  gradientFill: "boolean",
  palette: "int32",
  reverseSpectrum: "boolean",

  // Markers
  showMarkers: "boolean",
  markerLengthPercent: "float32",
  markerGlowWidthPercent: "float32",
  markerGlowIntensity: "float32",
  markerGlowFalloff: "int32",

  // Background
  grainIntensity: "float32",
  grainScale: "float32",
  grainPrismOnly: "boolean",
  grainBrightnessThreshold: "float32",
  vignette: "boolean",

  // Dithering
  ditherEnabled: "boolean",
  ditherPaletteMode: "int32",
  ditherPaletteSaturation: "float32",
  ditherStrength: "float32",
  ditherKernel: "int32",
  ditherOklabError: "boolean",
  ditherBwThreshold: "float32",

  // Debug output (read-only, written by WASM)
  entryU: "float32",
  exitU: "float32",
} as const;
