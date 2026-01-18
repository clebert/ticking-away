import type { WasmModule } from "./wasm.ts";

let cachedConfig: WatchfaceConfig | undefined;

export function getConfig(wasmModule: WasmModule, wasmMemory: WebAssembly.Memory): WatchfaceConfig {
  if (!cachedConfig) {
    cachedConfig = createConfig(wasmModule, wasmMemory);
  }

  return cachedConfig;
}

export type WatchfaceConfig = {
  -readonly [TKey in keyof typeof struct]: FieldType[(typeof struct)[TKey]];
};

type FieldType = { int: number; float: number; boolean: boolean };

// Order must match C struct layout in config.h
const struct = {
  // Time
  hour: "int",
  minute: "float",

  // Prism
  prismSizePercent: "float",
  rainbowSpread: "float",
  prismR: "int",
  prismG: "int",
  prismB: "int",
  glowWidthPercent: "float",
  glowIntensity: "float",
  glowFalloff: "int",

  // Rays
  rayGlowWidthPercent: "float",
  rayGlowIntensity: "float",
  rayGlowFalloff: "int",
  gradientFill: "boolean",
  palette: "int",
  reverseSpectrum: "boolean",

  // Markers
  showMarkers: "boolean",
  markerLengthPercent: "float",
  markerGlowWidthPercent: "float",
  markerGlowIntensity: "float",
  markerGlowFalloff: "int",

  // Background
  grainIntensity: "float",
  grainScale: "float",
  grainPrismOnly: "boolean",
  grainBrightnessThreshold: "float",
  vignette: "boolean",
} as const;

const offsets = Object.fromEntries(
  Object.keys(struct).map((key, index) => [key, index * 4]),
) as Readonly<Record<keyof typeof struct, number>>;

function createConfig(wasmModule: WasmModule, wasmMemory: WebAssembly.Memory): WatchfaceConfig {
  const baseOffset = wasmModule.get_config();

  return new Proxy({} as WatchfaceConfig, {
    get(_target, key: keyof typeof struct) {
      const offset = baseOffset + offsets[key];

      // Returns a fresh DataView into WASM memory because it can grow via `memory.grow()`
      const view = new DataView(wasmMemory.buffer);

      switch (struct[key]) {
        case "boolean": {
          return view.getInt32(offset, true) !== 0;
        }
        case "float": {
          return view.getFloat32(offset, true);
        }
        case "int": {
          return view.getInt32(offset, true);
        }
      }
    },

    set(_target, key: keyof typeof struct, newValue) {
      const offset = baseOffset + offsets[key];
      const view = new DataView(wasmMemory.buffer);

      switch (struct[key]) {
        case "boolean": {
          view.setInt32(offset, newValue ? 1 : 0, true);
          break;
        }
        case "float": {
          view.setFloat32(offset, newValue, true);
          break;
        }
        case "int": {
          view.setInt32(offset, newValue, true);
        }
      }

      return true;
    },
  });
}
