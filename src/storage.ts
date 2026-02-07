import type * as stores from "./stores.js";

const storageKey = "settings";

export interface Settings {
  modeLive: boolean;
  modeAccelerated: boolean;
  modeAccelerationFactor: number;

  timeHours: number;
  timeMinutes: number;

  prismSize: number;
  prismRainbowSpread: number;
  prismGray: number;
  prismBlueTint: number;
  prismGlowWidth: number;
  prismGlowFalloff: number;

  rainbowGlowWidth: number;
  rainbowGlowFalloff: number;
  rainbowPalette: number;

  effectsGrainIntensity: number;

  ditherEnabled: boolean;
  ditherPaletteMode: number;
  ditherStrength: number;
  ditherChromaWeight: number;

  displayHighDpi: boolean;
}

export function loadSettings(): Partial<Settings> {
  try {
    const item = localStorage.getItem(storageKey);

    if (item) {
      return JSON.parse(item) as Settings;
    }
  } catch {
    // Ignore localStorage errors
  }

  return {};
}

export function saveSettings({
  mode,
  time,
  prism,
  rainbow,
  display,
  effects,
  dither,
}: typeof stores): void {
  try {
    const settings: Settings = {
      modeLive: mode.live.value,
      modeAccelerated: mode.accelerated.value,
      modeAccelerationFactor: mode.accelerationFactor.value,

      timeHours: time.hours.value,
      timeMinutes: time.minutes.value,

      prismSize: prism.size.value,
      prismRainbowSpread: prism.rainbowSpread.value,
      prismGray: prism.gray.value,
      prismBlueTint: prism.blueTint.value,
      prismGlowWidth: prism.glowWidth.value,
      prismGlowFalloff: prism.glowFalloff.value,

      rainbowGlowWidth: rainbow.glowWidth.value,
      rainbowGlowFalloff: rainbow.glowFalloff.value,
      rainbowPalette: rainbow.palette.value,

      effectsGrainIntensity: effects.grainIntensity.value,

      ditherEnabled: dither.enabled.value,
      ditherPaletteMode: dither.paletteMode.value,
      ditherStrength: dither.strength.value,
      ditherChromaWeight: dither.chromaWeight.value,

      displayHighDpi: display.highDpi.value,
    };

    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}
