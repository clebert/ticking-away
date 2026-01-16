import { batch, computed, type ReadonlySignal, signal } from "@preact/signals-core";
import { loadSettings } from "./storage.js";

const defaults = {
  mode: {
    accelerated: false,
    accelerationFactor: 1,
  },
  prism: {
    size: 90,
    rainbowSpread: 30,
    gray: 255,
    blueTint: 70,
    glowWidth: 12,
    glowIntensity: 100,
    glowFalloff: 3,
    sparkleSize: 300,
  },
  rays: {
    glowWidth: 2,
    glowIntensity: 100,
    glowFalloff: 1,
    innerSpectrum: true,
    artisticDispersion: false,
  },
  markers: {
    length: 15,
    style: 0,
    glowWidth: 1,
    glowIntensity: 100,
    glowFalloff: 3,
  },
  background: {
    grainIntensity: 50,
    vignetteIntensity: 100,
    grainAnimated: false,
  },
  display: {
    markers: true,
    seconds: false,
    dithering: 0,
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
  seconds: signal(initialTime.getSeconds()),

  // Actions
  setHours(e: Event): void {
    time.hours.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setMinutes(e: Event): void {
    time.minutes.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setSeconds(e: Event): void {
    time.seconds.value = parseInt((e.target as HTMLInputElement).value, 10);
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

  // Signals: sparkle
  sparkleSize: signal(settings.prismSparkleSize ?? defaults.prism.sparkleSize),

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

  setSparkleSize(e: Event): void {
    prism.sparkleSize.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const rays = {
  // Signals: glow
  glowWidth: signal(settings.raysGlowWidth ?? defaults.rays.glowWidth),
  glowIntensity: signal(settings.raysGlowIntensity ?? defaults.rays.glowIntensity),
  glowFalloff: signal(settings.raysGlowFalloff ?? defaults.rays.glowFalloff),

  // Signals: color
  innerSpectrum: signal(settings.raysInnerSpectrum ?? defaults.rays.innerSpectrum),
  artisticDispersion: signal(settings.raysArtisticDispersion ?? defaults.rays.artisticDispersion),

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

  toggleInnerSpectrum(): void {
    rays.innerSpectrum.value = !rays.innerSpectrum.value;
  },

  toggleArtisticDispersion(): void {
    rays.artisticDispersion.value = !rays.artisticDispersion.value;
  },
};

export const markers = {
  // Signals: geometry
  length: signal(settings.markersLength ?? defaults.markers.length),
  style: signal(settings.markersStyle ?? defaults.markers.style), // 0=all, 1=cardinal, 2=prism

  // Signals: glow
  glowWidth: signal(settings.markersGlowWidth ?? defaults.markers.glowWidth),
  glowIntensity: signal(settings.markersGlowIntensity ?? defaults.markers.glowIntensity),
  glowFalloff: signal(settings.markersGlowFalloff ?? defaults.markers.glowFalloff),

  // Actions
  setLength(e: Event): void {
    markers.length.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setStyle(e: Event): void {
    markers.style.value = parseInt((e.target as HTMLSelectElement).value, 10);
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
  vignetteIntensity: signal(
    settings.backgroundVignetteIntensity ?? defaults.background.vignetteIntensity,
  ),

  // Signals: grain options
  grainAnimated: signal(settings.backgroundGrainAnimated ?? defaults.background.grainAnimated),

  // Computed
  grainDisabled: computed((): boolean => display.pebble.value || display.dithering.value !== 0),
  vignetteDisabled: computed((): boolean => display.pebble.value || display.dithering.value !== 0),

  // Actions
  setGrainIntensity(e: Event): void {
    background.grainIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setVignetteIntensity(e: Event): void {
    background.vignetteIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  toggleGrainAnimated(): void {
    background.grainAnimated.value = !background.grainAnimated.value;
  },
};

export const display = {
  // Signals
  markers: signal(settings.displayMarkers ?? defaults.display.markers),
  seconds: signal(settings.displaySeconds ?? defaults.display.seconds),
  dithering: signal(settings.displayDithering ?? defaults.display.dithering),
  pebble: signal(settings.displayPebble ?? defaults.display.pebble),
  highDpi: signal(settings.displayHighDpi ?? defaults.display.highDpi),

  // Computed
  secondsDisabled: computed((): boolean => mode.live.value && mode.accelerated.value),

  // Actions
  toggleMarkers(): void {
    display.markers.value = !display.markers.value;
  },

  toggleSeconds(): void {
    display.seconds.value = !display.seconds.value;
  },

  setDithering(e: Event): void {
    display.dithering.value = parseInt((e.target as HTMLSelectElement).value, 10);
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
      prism.sparkleSize.value = defaults.prism.sparkleSize;

      // Rays
      rays.glowWidth.value = defaults.rays.glowWidth;
      rays.glowIntensity.value = defaults.rays.glowIntensity;
      rays.glowFalloff.value = defaults.rays.glowFalloff;
      rays.innerSpectrum.value = defaults.rays.innerSpectrum;
      rays.artisticDispersion.value = defaults.rays.artisticDispersion;

      // Markers
      markers.length.value = defaults.markers.length;
      markers.style.value = defaults.markers.style;
      markers.glowWidth.value = defaults.markers.glowWidth;
      markers.glowIntensity.value = defaults.markers.glowIntensity;
      markers.glowFalloff.value = defaults.markers.glowFalloff;

      // Background
      background.grainIntensity.value = defaults.background.grainIntensity;
      background.vignetteIntensity.value = defaults.background.vignetteIntensity;
      background.grainAnimated.value = defaults.background.grainAnimated;

      // Display
      display.markers.value = defaults.display.markers;
      display.seconds.value = defaults.display.seconds;
      display.dithering.value = defaults.display.dithering;
      display.pebble.value = defaults.display.pebble;
      display.highDpi.value = defaults.display.highDpi;
    });
  },
};
