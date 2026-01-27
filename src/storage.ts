import type * as stores from "./stores.js";

const storageKey = "settings";

export interface Settings {
  rendererType: number;

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
  prismGlowIntensity: number;
  prismGlowFalloff: number;

  raysGlowWidth: number;
  raysGlowIntensity: number;
  raysGlowFalloff: number;
  raysGradientFill: boolean;
  raysPalette: number;
  raysReverseSpectrum: boolean;

  markersLength: number;
  markersGlowWidth: number;
  markersGlowIntensity: number;
  markersGlowFalloff: number;

  displayMarkers: boolean;
  displayHighDpi: boolean;

  backgroundGrainIntensity: number;
  backgroundGrainPrismOnly: boolean;
  backgroundGrainBrightnessThreshold: number;

  ditherEnabled: boolean;
  ditherType: number;
  ditherPaletteMode: number;
  ditherStrength: number;
  ditherAlgorithm: number;
  ditherOklabError: boolean;
  ditherOrderedMatrix: number;
  ditherSpread: number;
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
  renderer,
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
      rendererType: renderer.type.value,

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
      prismGlowIntensity: prism.glowIntensity.value,
      prismGlowFalloff: prism.glowFalloff.value,

      raysGlowWidth: rays.glowWidth.value,
      raysGlowIntensity: rays.glowIntensity.value,
      raysGlowFalloff: rays.glowFalloff.value,
      raysGradientFill: rays.gradientFill.value,
      raysPalette: rays.palette.value,
      raysReverseSpectrum: rays.reverseSpectrum.value,

      markersLength: markers.length.value,
      markersGlowWidth: markers.glowWidth.value,
      markersGlowIntensity: markers.glowIntensity.value,
      markersGlowFalloff: markers.glowFalloff.value,

      backgroundGrainIntensity: background.grainIntensity.value,
      backgroundGrainPrismOnly: background.grainPrismOnly.value,
      backgroundGrainBrightnessThreshold: background.grainBrightnessThreshold.value,

      ditherEnabled: dither.enabled.value,
      ditherType: dither.type.value,
      ditherPaletteMode: dither.paletteMode.value,
      ditherStrength: dither.strength.value,
      ditherAlgorithm: dither.algorithm.value,
      ditherOklabError: dither.oklabError.value,
      ditherOrderedMatrix: dither.orderedMatrix.value,
      ditherSpread: dither.spread.value,
      ditherChromaWeight: dither.chromaWeight.value,

      displayMarkers: display.markers.value,
      displayHighDpi: display.highDpi.value,
    };

    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}
