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
    blueTint: 100,
    glowWidth: 6,
    glowFalloff: 3, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
  },
  rays: {
    glowWidth: 1,
    glowFalloff: 1, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
    gradientFill: true,
    palette: 1, // 0=OkLCH Balanced, 1=Spectral, 2=Spectra6
    reverseSpectrum: true, // Album art style: red on top, violet on bottom
  },
  markers: {
    length: 10,
    glowWidth: 1,
    glowFalloff: 1, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
  },
  background: {
    grainIntensity: 100,
    grainBrightnessThreshold: 30,
  },
  dither: {
    enabled: false,
    paletteMode: 0, // 0 = IDEAL, 1 = SPECTRA6_INKY, 2 = SPECTRA6_EPDOPT
    strength: 20, // 0-100, maps to 0.0-1.0
    oklabError: false, // false = linear RGB error diffusion, true = OkLab error diffusion
    chromaWeight: 200, // 50-400, maps to 0.5-4.0 (200 = default 2.0, higher = prioritize hue)
  },
  display: {
    markers: false,
    highDpi: false,
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
  live: signal(settings.modeLive ?? true),
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

// Use persisted time if not in live mode, otherwise use current time
const persistedLive = settings.modeLive ?? true;

export const time = {
  // Signals
  hours: signal(
    persistedLive
      ? initialTime.getHours() % 12
      : (settings.timeHours ?? initialTime.getHours() % 12),
  ),
  minutes: signal(
    persistedLive ? initialTime.getMinutes() : (settings.timeMinutes ?? initialTime.getMinutes()),
  ),
  seconds: signal(initialTime.getSeconds()), // Used internally for animation
  forceOppositeBounce: signal(settings.timeForceOppositeBounce ?? false),

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

  toggleForceOppositeBounce(): void {
    time.forceOppositeBounce.value = !time.forceOppositeBounce.value;
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

  setGlowFalloff(e: Event): void {
    prism.glowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },
};

export const rays = {
  // Signals: glow
  glowWidth: signal(settings.raysGlowWidth ?? defaults.rays.glowWidth),
  glowFalloff: signal(settings.raysGlowFalloff ?? defaults.rays.glowFalloff),

  // Signals: rendering mode
  gradientFill: signal(settings.raysGradientFill ?? defaults.rays.gradientFill),
  palette: signal(settings.raysPalette ?? defaults.rays.palette),
  reverseSpectrum: signal(settings.raysReverseSpectrum ?? defaults.rays.reverseSpectrum),

  // Actions
  setGlowWidth(e: Event): void {
    rays.glowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
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
};

export const markers = {
  // Signals: geometry
  length: signal(settings.markersLength ?? defaults.markers.length),

  // Signals: glow
  glowWidth: signal(settings.markersGlowWidth ?? defaults.markers.glowWidth),
  glowFalloff: signal(settings.markersGlowFalloff ?? defaults.markers.glowFalloff),

  // Actions
  setLength(e: Event): void {
    markers.length.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowWidth(e: Event): void {
    markers.glowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowFalloff(e: Event): void {
    markers.glowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },
};

export const background = {
  // Signals: effect intensities
  grainIntensity: signal(settings.backgroundGrainIntensity ?? defaults.background.grainIntensity),
  grainBrightnessThreshold: signal(
    settings.backgroundGrainBrightnessThreshold ?? defaults.background.grainBrightnessThreshold,
  ),

  // Computed
  grainDisabled: computed((): boolean => dither.enabled.value),

  // Actions
  setGrainIntensity(e: Event): void {
    background.grainIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGrainBrightnessThreshold(e: Event): void {
    background.grainBrightnessThreshold.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const dither = {
  // Signals
  enabled: signal(settings.ditherEnabled ?? defaults.dither.enabled),
  paletteMode: signal(settings.ditherPaletteMode ?? defaults.dither.paletteMode),
  strength: signal(settings.ditherStrength ?? defaults.dither.strength),
  oklabError: signal(settings.ditherOklabError ?? defaults.dither.oklabError),
  chromaWeight: signal(settings.ditherChromaWeight ?? defaults.dither.chromaWeight),

  // Actions
  toggleEnabled(): void {
    dither.enabled.value = !dither.enabled.value;
  },

  setPaletteMode(e: Event): void {
    dither.paletteMode.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },

  setStrength(e: Event): void {
    dither.strength.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  toggleOklabError(): void {
    dither.oklabError.value = !dither.oklabError.value;
  },

  setChromaWeight(e: Event): void {
    dither.chromaWeight.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const display = {
  // Signals
  markers: signal(settings.displayMarkers ?? defaults.display.markers),
  highDpi: signal(settings.displayHighDpi ?? defaults.display.highDpi),

  // Actions
  toggleMarkers(): void {
    display.markers.value = !display.markers.value;
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

      // Time
      time.forceOppositeBounce.value = false;

      // Prism
      prism.size.value = defaults.prism.size;
      prism.rainbowSpread.value = defaults.prism.rainbowSpread;
      prism.gray.value = defaults.prism.gray;
      prism.blueTint.value = defaults.prism.blueTint;
      prism.glowWidth.value = defaults.prism.glowWidth;
      prism.glowFalloff.value = defaults.prism.glowFalloff;

      // Rays
      rays.glowWidth.value = defaults.rays.glowWidth;
      rays.glowFalloff.value = defaults.rays.glowFalloff;
      rays.gradientFill.value = defaults.rays.gradientFill;
      rays.palette.value = defaults.rays.palette;
      rays.reverseSpectrum.value = defaults.rays.reverseSpectrum;

      // Markers
      markers.length.value = defaults.markers.length;
      markers.glowWidth.value = defaults.markers.glowWidth;
      markers.glowFalloff.value = defaults.markers.glowFalloff;

      // Background
      background.grainIntensity.value = defaults.background.grainIntensity;
      background.grainBrightnessThreshold.value = defaults.background.grainBrightnessThreshold;

      // Dither
      dither.enabled.value = defaults.dither.enabled;
      dither.paletteMode.value = defaults.dither.paletteMode;
      dither.strength.value = defaults.dither.strength;
      dither.oklabError.value = defaults.dither.oklabError;
      dither.chromaWeight.value = defaults.dither.chromaWeight;

      // Display
      display.markers.value = defaults.display.markers;
      display.highDpi.value = defaults.display.highDpi;
    });
  },
};
