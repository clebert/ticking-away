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
    gray: 248,
    blueTint: 160,
    glowWidth: 7,
    glowFalloff: 3, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
  },

  rainbow: {
    glowWidth: 1,
    glowFalloff: 1, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
    palette: 2, // 0=OkLCH Balanced, 1=Spectral, 2=Spectra6
  },

  effects: {
    grainIntensity: 100,
  },

  dither: {
    enabled: false,
    paletteMode: 2, // 0 = IDEAL, 1 = SPECTRA6_INKY, 2 = SPECTRA6_EPDOPT
    strength: 98, // 0-100, maps to 0.0-1.0
    chromaWeight: 100, // 50-400, maps to 0.5-4.0
  },

  display: {
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

export const rainbow = {
  // Signals: glow
  glowWidth: signal(settings.rainbowGlowWidth ?? defaults.rainbow.glowWidth),
  glowFalloff: signal(settings.rainbowGlowFalloff ?? defaults.rainbow.glowFalloff),

  // Signals: rendering mode
  palette: signal(settings.rainbowPalette ?? defaults.rainbow.palette),

  // Actions
  setGlowWidth(e: Event): void {
    rainbow.glowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setGlowFalloff(e: Event): void {
    rainbow.glowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },

  setPalette(e: Event): void {
    rainbow.palette.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },
};

export const effects = {
  // Signals
  grainIntensity: signal(settings.effectsGrainIntensity ?? defaults.effects.grainIntensity),

  // Computed
  grainDisabled: computed((): boolean => dither.enabled.value),

  // Actions
  setGrainIntensity(e: Event): void {
    effects.grainIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const dither = {
  // Signals
  enabled: signal(settings.ditherEnabled ?? defaults.dither.enabled),
  paletteMode: signal(settings.ditherPaletteMode ?? defaults.dither.paletteMode),
  strength: signal(settings.ditherStrength ?? defaults.dither.strength),
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

  setChromaWeight(e: Event): void {
    dither.chromaWeight.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const display = {
  // Signals
  highDpi: signal(settings.displayHighDpi ?? defaults.display.highDpi),

  // Actions
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
      prism.glowFalloff.value = defaults.prism.glowFalloff;

      // Rainbow
      rainbow.glowWidth.value = defaults.rainbow.glowWidth;
      rainbow.glowFalloff.value = defaults.rainbow.glowFalloff;
      rainbow.palette.value = defaults.rainbow.palette;

      // Effects
      effects.grainIntensity.value = defaults.effects.grainIntensity;

      // Dither
      dither.enabled.value = defaults.dither.enabled;
      dither.paletteMode.value = defaults.dither.paletteMode;
      dither.strength.value = defaults.dither.strength;
      dither.chromaWeight.value = defaults.dither.chromaWeight;

      // Display
      display.highDpi.value = defaults.display.highDpi;
    });
  },
};
