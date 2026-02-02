import type * as stores from "./stores.js";

const storageKey = "settings";

export interface Settings {
  modeLive: boolean;
  modeAccelerated: boolean;
  modeAccelerationFactor: number;

  timeHours: number;
  timeMinutes: number;
  timeBounceMode: number;

  prismSize: number;
  prismRainbowSpread: number;
  prismGray: number;
  prismBlueTint: number;
  prismGlowWidth: number;
  prismGlowFalloff: number;

  raysGlowWidth: number;
  raysGlowFalloff: number;
  raysGradientFill: boolean;
  raysPalette: number;
  raysReverseSpectrum: boolean;

  markersLength: number;
  markersGlowWidth: number;
  markersGlowFalloff: number;

  displayMarkers: boolean;
  displayHighDpi: boolean;

  backgroundGrainIntensity: number;
  backgroundGrainBrightnessThreshold: number;

  ditherEnabled: boolean;
  ditherPaletteMode: number;
  ditherStrength: number;
  ditherOklabError: boolean;
  ditherChromaWeight: number;
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
  rays,
  markers,
  display,
  background,
  dither,
}: typeof stores): void {
  try {
    const settings: Settings = {
      modeLive: mode.live.value,
      modeAccelerated: mode.accelerated.value,
      modeAccelerationFactor: mode.accelerationFactor.value,

      timeHours: time.hours.value,
      timeMinutes: time.minutes.value,
      timeBounceMode: time.bounceMode.value,

      prismSize: prism.size.value,
      prismRainbowSpread: prism.rainbowSpread.value,
      prismGray: prism.gray.value,
      prismBlueTint: prism.blueTint.value,
      prismGlowWidth: prism.glowWidth.value,
      prismGlowFalloff: prism.glowFalloff.value,

      raysGlowWidth: rays.glowWidth.value,
      raysGlowFalloff: rays.glowFalloff.value,
      raysGradientFill: rays.gradientFill.value,
      raysPalette: rays.palette.value,
      raysReverseSpectrum: rays.reverseSpectrum.value,

      markersLength: markers.length.value,
      markersGlowWidth: markers.glowWidth.value,
      markersGlowFalloff: markers.glowFalloff.value,

      backgroundGrainIntensity: background.grainIntensity.value,
      backgroundGrainBrightnessThreshold: background.grainBrightnessThreshold.value,

      ditherEnabled: dither.enabled.value,
      ditherPaletteMode: dither.paletteMode.value,
      ditherStrength: dither.strength.value,
      ditherOklabError: dither.oklabError.value,
      ditherChromaWeight: dither.chromaWeight.value,

      displayMarkers: display.markers.value,
      displayHighDpi: display.highDpi.value,
    };

    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}
