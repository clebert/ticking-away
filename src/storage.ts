import type * as stores from "./stores.js";

const storageKey = "settings";

export interface Settings {
  modeLive: boolean;
  modeAccelerated: boolean;
  modeAccelerationFactor: number;

  timeHour: number;
  timeMinute: number;

  prismSize: number;
  prismGray: number;
  prismBlueTint: number;
  prismGlowWidth: number;
  prismGlowFalloff: number;

  rainbowSpread: number;
  rainbowHandGlowWidth: number;
  rainbowHandGlowFalloff: number;
  rainbowPalette: number;

  effectsGrainIntensity: number;

  ditherEnabled: boolean;
  ditherPaletteId: number;
  ditherStrength: number;
  ditherChromaEmphasis: number;

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

      timeHour: time.hour.value,
      timeMinute: time.minute.value,

      prismSize: prism.size.value,
      prismGray: prism.gray.value,
      prismBlueTint: prism.blueTint.value,
      prismGlowWidth: prism.glowWidth.value,
      prismGlowFalloff: prism.glowFalloff.value,

      rainbowSpread: rainbow.spread.value,
      rainbowHandGlowWidth: rainbow.handGlowWidth.value,
      rainbowHandGlowFalloff: rainbow.handGlowFalloff.value,
      rainbowPalette: rainbow.palette.value,

      effectsGrainIntensity: effects.grainIntensity.value,

      ditherEnabled: dither.enabled.value,
      ditherPaletteId: dither.paletteId.value,
      ditherStrength: dither.strength.value,
      ditherChromaEmphasis: dither.chromaEmphasis.value,

      displayHighDpi: display.highDpi.value,
    };

    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}
