import { batch, computed, type ReadonlySignal, signal } from "@preact/signals-core";
import { loadSettings } from "./storage.js";

const defaults = {
  mode: {
    accelerated: false,
    accelerationFactor: 1,
  },
  prism: {
    size: 90,
    rainbowSpread: 50,
    gray: 255,
    blueTint: 80,
    glowWidth: 6,
    glowIntensity: 100,
    glowFalloff: 3,
  },
  rays: {
    glowWidth: 1,
    glowIntensity: 100,
    glowFalloff: 3,
    gradientFill: true,
    palette: 2, // 0=OkLCH Balanced, 1=Saturated, 2=Spectral, 3=Neon, 4=Muted
    reverseSpectrum: true, // Album art style: red on top, violet on bottom
    cornerHugThreshold: 80, // 50-95 (edge position % for corner hug detection)
  },
  markers: {
    length: 15,
    glowWidth: 1,
    glowIntensity: 100,
    glowFalloff: 3,
  },
  background: {
    grainIntensity: 80,
    grainPrismOnly: false,
    grainBrightnessThreshold: 20,
  },
  display: {
    markers: true,
    pebble: false,
    highDpi: true,
  },
};

const initialTime = new Date();
const settings = loadSettings();

let wakeLock: WakeLockSentinel | undefined;

const requestWakeLock = async (): Promise<void> => {
  if ("wakeLock" in navigator) {
    try {
      wakeLock = await navigator.wakeLock.request("screen");
    } catch {
      // Wake lock request failed (e.g., low battery, tab hidden)
    }
  }
};

export const mode = {
  // Signals: display mode
  fullscreen: ((): ReadonlySignal<boolean> => {
    const fullscreen = signal(document.fullscreenElement !== null);

    document.addEventListener("fullscreenchange", () => {
      fullscreen.value = document.fullscreenElement !== null;

      if (fullscreen.value) {
        requestWakeLock();
      } else if (wakeLock) {
        wakeLock.release();

        wakeLock = undefined;
      }
    });

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && fullscreen.value) {
        requestWakeLock();
      }
    });

    return fullscreen;
  })(),

  clockOnly: signal(new URLSearchParams(window.location.search).has("clock")),

  // Signals: time behavior
  live: signal(true),
  accelerated: signal(settings.modeAccelerated ?? defaults.mode.accelerated),
  accelerationFactor: signal(settings.modeAccelerationFactor ?? defaults.mode.accelerationFactor),

  // Signals: performance
  frameDuration: signal(0),

  // Computed
  hideControls: computed((): boolean => mode.fullscreen.value || mode.clockOnly.value),
  fullscreenDisabled: computed((): boolean => !mode.live.value || mode.accelerated.value),

  fpsText: computed((): string => {
    if (!mode.live.value || mode.frameDuration.value === 0) {
      return "";
    }

    const fps = Math.round(1000 / mode.frameDuration.value);

    return `${fps} fps`;
  }),

  // Actions
  enterFullscreen: async (): Promise<void> => {
    await document.documentElement.requestFullscreen();
  },

  toggleLive(): void {
    mode.live.value = !mode.live.value;
  },

  toggleAccelerated(): void {
    mode.accelerated.value = !mode.accelerated.value;
  },

  setAccelerationFactor(e: Event): void {
    mode.accelerationFactor.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },

  toggleClockOnly(): void {
    if (mode.fullscreen.value) {
      return;
    }

    mode.clockOnly.value = !mode.clockOnly.value;

    const url = new URL(window.location.href);

    if (mode.clockOnly.value) {
      url.searchParams.set("clock", "");
    } else {
      url.searchParams.delete("clock");
    }

    window.history.replaceState(null, "", url);
  },
};

export const time = {
  // Signals
  hours: signal(initialTime.getHours() % 12),
  minutes: signal(initialTime.getMinutes()),
  seconds: signal(initialTime.getSeconds()), // Used internally for animation

  // Actions
  setHours(e: Event): void {
    time.hours.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setMinutes(e: Event): void {
    time.minutes.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setNow(): void {
    const currentTime = new Date();

    batch(() => {
      time.hours.value = currentTime.getHours() % 12;
      time.minutes.value = currentTime.getMinutes();
      time.seconds.value = currentTime.getSeconds();
    });
  },
};

export const prism = {
  // Signals: geometry
  size: signal(settings.prismSize ?? defaults.prism.size),
  rainbowSpread: signal(settings.prismRainbowSpread ?? defaults.prism.rainbowSpread),

  // Signals: color
  gray: signal(settings.prismGray ?? defaults.prism.gray),
  blueTint: signal(settings.prismBlueTint ?? defaults.prism.blueTint),

  // Signals: glow
  glowWidth: signal(settings.prismGlowWidth ?? defaults.prism.glowWidth),
  glowIntensity: signal(settings.prismGlowIntensity ?? defaults.prism.glowIntensity),
  glowFalloff: signal(settings.prismGlowFalloff ?? defaults.prism.glowFalloff),

  // Actions
  setSize(e: Event): void {
    prism.size.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setRainbowSpread(e: Event): void {
    prism.rainbowSpread.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGray(e: Event): void {
    prism.gray.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setBlueTint(e: Event): void {
    prism.blueTint.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowWidth(e: Event): void {
    prism.glowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowIntensity(e: Event): void {
    prism.glowIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowFalloff(e: Event): void {
    prism.glowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },
};

export const rays = {
  // Signals: glow
  glowWidth: signal(settings.raysGlowWidth ?? defaults.rays.glowWidth),
  glowIntensity: signal(settings.raysGlowIntensity ?? defaults.rays.glowIntensity),
  glowFalloff: signal(settings.raysGlowFalloff ?? defaults.rays.glowFalloff),

  // Signals: rendering mode
  gradientFill: signal(settings.raysGradientFill ?? defaults.rays.gradientFill),
  palette: signal(settings.raysPalette ?? defaults.rays.palette),
  reverseSpectrum: signal(settings.raysReverseSpectrum ?? defaults.rays.reverseSpectrum),

  // Signals: bounce detection
  cornerHugThreshold: signal(settings.raysCornerHugThreshold ?? defaults.rays.cornerHugThreshold),

  // Actions
  setGlowWidth(e: Event): void {
    rays.glowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowIntensity(e: Event): void {
    rays.glowIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowFalloff(e: Event): void {
    rays.glowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },

  toggleGradientFill(): void {
    rays.gradientFill.value = !rays.gradientFill.value;
  },

  setPalette(e: Event): void {
    rays.palette.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },

  toggleReverseSpectrum(): void {
    rays.reverseSpectrum.value = !rays.reverseSpectrum.value;
  },

  setCornerHugThreshold(e: Event): void {
    rays.cornerHugThreshold.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const markers = {
  // Signals: geometry
  length: signal(settings.markersLength ?? defaults.markers.length),

  // Signals: glow
  glowWidth: signal(settings.markersGlowWidth ?? defaults.markers.glowWidth),
  glowIntensity: signal(settings.markersGlowIntensity ?? defaults.markers.glowIntensity),
  glowFalloff: signal(settings.markersGlowFalloff ?? defaults.markers.glowFalloff),

  // Actions
  setLength(e: Event): void {
    markers.length.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowWidth(e: Event): void {
    markers.glowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowIntensity(e: Event): void {
    markers.glowIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowFalloff(e: Event): void {
    markers.glowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },
};

export const background = {
  // Signals: effect intensities
  grainIntensity: signal(settings.backgroundGrainIntensity ?? defaults.background.grainIntensity),
  grainPrismOnly: signal(settings.backgroundGrainPrismOnly ?? defaults.background.grainPrismOnly),
  grainBrightnessThreshold: signal(
    settings.backgroundGrainBrightnessThreshold ?? defaults.background.grainBrightnessThreshold,
  ),

  // Computed
  grainDisabled: computed((): boolean => display.pebble.value),

  // Actions
  setGrainIntensity(e: Event): void {
    background.grainIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  toggleGrainPrismOnly(): void {
    background.grainPrismOnly.value = !background.grainPrismOnly.value;
  },

  setGrainBrightnessThreshold(e: Event): void {
    background.grainBrightnessThreshold.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const display = {
  // Signals
  markers: signal(settings.displayMarkers ?? defaults.display.markers),
  pebble: signal(settings.displayPebble ?? defaults.display.pebble),
  highDpi: signal(settings.displayHighDpi ?? defaults.display.highDpi),

  // Actions
  toggleMarkers(): void {
    display.markers.value = !display.markers.value;
  },

  togglePebble(): void {
    display.pebble.value = !display.pebble.value;
  },

  toggleHighDpi(): void {
    display.highDpi.value = !display.highDpi.value;
  },
};

export const resetAll = {
  reset(): void {
    batch(() => {
      // Mode
      mode.accelerated.value = defaults.mode.accelerated;
      mode.accelerationFactor.value = defaults.mode.accelerationFactor;

      // Prism
      prism.size.value = defaults.prism.size;
      prism.rainbowSpread.value = defaults.prism.rainbowSpread;
      prism.gray.value = defaults.prism.gray;
      prism.blueTint.value = defaults.prism.blueTint;
      prism.glowWidth.value = defaults.prism.glowWidth;
      prism.glowIntensity.value = defaults.prism.glowIntensity;
      prism.glowFalloff.value = defaults.prism.glowFalloff;

      // Rays
      rays.glowWidth.value = defaults.rays.glowWidth;
      rays.glowIntensity.value = defaults.rays.glowIntensity;
      rays.glowFalloff.value = defaults.rays.glowFalloff;
      rays.gradientFill.value = defaults.rays.gradientFill;
      rays.palette.value = defaults.rays.palette;
      rays.reverseSpectrum.value = defaults.rays.reverseSpectrum;
      rays.cornerHugThreshold.value = defaults.rays.cornerHugThreshold;

      // Markers
      markers.length.value = defaults.markers.length;
      markers.glowWidth.value = defaults.markers.glowWidth;
      markers.glowIntensity.value = defaults.markers.glowIntensity;
      markers.glowFalloff.value = defaults.markers.glowFalloff;

      // Background
      background.grainIntensity.value = defaults.background.grainIntensity;
      background.grainPrismOnly.value = defaults.background.grainPrismOnly;
      background.grainBrightnessThreshold.value = defaults.background.grainBrightnessThreshold;

      // Display
      display.markers.value = defaults.display.markers;
      display.pebble.value = defaults.display.pebble;
      display.highDpi.value = defaults.display.highDpi;
    });
  },
};
