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

// Order must match C struct layout in bin/wasm/main.c
// Nested structs match definitions in lib/config.h
const fields = {
  // Time
  hour: "int32",
  minute: "float32",

  // PrismConfig
  prism: {
    size: "float32", // 0.1-0.9 (fraction of watch radius)
    rainbowSpread: "float32", // 0.0-1.0
  },

  // GlowConfig
  glow: {
    r: "int32", // 0-255
    g: "int32",
    b: "int32",
    width: "float32", // 0.05-0.50
    intensity: "float32", // 0.1-1.0
    falloff: "int32", // FalloffType enum
  },

  // RayConfig
  ray: {
    glowWidth: "float32", // 0.0-0.10
    intensity: "float32", // 0.0-1.0
    falloff: "int32", // FalloffType enum
    palette: "int32", // 0-4
    gradientFill: "boolean",
    reverse: "boolean",
  },

  // MarkerConfig
  marker: {
    visible: "boolean",
    length: "float32", // 0.0-0.20
    glowWidth: "float32", // 0.0-0.05
    glowIntensity: "float32", // 0.0-1.0
    falloff: "int32", // FalloffType enum
  },

  // GrainConfig
  grain: {
    intensity: "float32", // 0.0-1.0
    scale: "float32", // DPR
    threshold: "float32", // 0.01-1.0
    prismOnly: "boolean",
  },

  // VignetteConfig
  vignette: {
    enabled: "boolean",
    strength: "float32", // 0.0-1.0
    background: "float32", // 0.0-1.0
  },

  // SceneDitherConfig
  dither: {
    enabled: "boolean",
    type: "int32", // DitherType enum (0=error, 1=ordered)
    mode: "int32", // DitherPaletteMode enum
    // Error diffusion params
    strength: "float32", // 0.0-1.0
    algorithm: "int32", // DitherErrorAlgorithm enum
    oklabError: "boolean",
    // Ordered params
    orderedMatrix: "int32", // DitherOrderedMatrixType enum (0=2x2, 1=4x4, 2=8x8)
    spread: "float32", // 0.0-1.0
    // Shared
    chromaWeight: "float32", // 0.5-4.0
  },

  // Debug output (read-only, written by WASM)
  entryU: "float32",
  exitU: "float32",
} as const;
