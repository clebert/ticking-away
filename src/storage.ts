import type * as stores from "./stores.js";

const storageKey = "settings";

export interface Settings {
  modeAccelerated: boolean;
  modeAccelerationFactor: number;

  prismSize: number;
  prismRainbowSpread: number;
  prismGray: number;
  prismBlueTint: number;
  prismGlowWidth: number;
  prismGlowIntensity: number;
  prismGlowFalloff: number;
  prismSparkleSize: number;

  raysGlowWidth: number;
  raysGlowIntensity: number;
  raysGlowFalloff: number;
  raysInnerSpectrum: boolean;
  raysArtisticDispersion: boolean;

  displayMarkers: boolean;
  displaySeconds: boolean;
  displayDithering: boolean;
  displayPebble: boolean;
  displayHighDpi: boolean;

  backgroundGrainIntensity: number;
  backgroundVignetteIntensity: number;
  backgroundGrainAnimated: boolean;
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

export function saveSettings({ mode, prism, rays, display, background }: typeof stores): void {
  try {
    const settings: Settings = {
      modeAccelerated: mode.accelerated.value,
      modeAccelerationFactor: mode.accelerationFactor.value,

      prismSize: prism.size.value,
      prismRainbowSpread: prism.rainbowSpread.value,
      prismGray: prism.gray.value,
      prismBlueTint: prism.blueTint.value,
      prismGlowWidth: prism.glowWidth.value,
      prismGlowIntensity: prism.glowIntensity.value,
      prismGlowFalloff: prism.glowFalloff.value,
      prismSparkleSize: prism.sparkleSize.value,

      raysGlowWidth: rays.glowWidth.value,
      raysGlowIntensity: rays.glowIntensity.value,
      raysGlowFalloff: rays.glowFalloff.value,
      raysInnerSpectrum: rays.innerSpectrum.value,
      raysArtisticDispersion: rays.artisticDispersion.value,

      backgroundGrainIntensity: background.grainIntensity.value,
      backgroundVignetteIntensity: background.vignetteIntensity.value,
      backgroundGrainAnimated: background.grainAnimated.value,

      displayMarkers: display.markers.value,
      displaySeconds: display.seconds.value,
      displayDithering: display.dithering.value,
      displayPebble: display.pebble.value,
      displayHighDpi: display.highDpi.value,
    };

    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}
