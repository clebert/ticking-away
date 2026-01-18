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

  raysGlowWidth: number;
  raysGlowIntensity: number;
  raysGlowFalloff: number;
  raysGradientFill: boolean;
  raysPalette: number;

  markersLength: number;
  markersGlowWidth: number;
  markersGlowIntensity: number;
  markersGlowFalloff: number;

  displayMarkers: boolean;
  displayPebble: boolean;
  displayHighDpi: boolean;

  backgroundGrainIntensity: number;
  backgroundGrainPrismOnly: boolean;
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
  prism,
  rays,
  markers,
  display,
  background,
}: typeof stores): void {
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

      raysGlowWidth: rays.glowWidth.value,
      raysGlowIntensity: rays.glowIntensity.value,
      raysGlowFalloff: rays.glowFalloff.value,
      raysGradientFill: rays.gradientFill.value,
      raysPalette: rays.palette.value,

      markersLength: markers.length.value,
      markersGlowWidth: markers.glowWidth.value,
      markersGlowIntensity: markers.glowIntensity.value,
      markersGlowFalloff: markers.glowFalloff.value,

      backgroundGrainIntensity: background.grainIntensity.value,
      backgroundGrainPrismOnly: background.grainPrismOnly.value,

      displayMarkers: display.markers.value,
      displayPebble: display.pebble.value,
      displayHighDpi: display.highDpi.value,
    };

    localStorage.setItem(storageKey, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}
