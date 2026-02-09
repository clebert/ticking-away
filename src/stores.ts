import { batch, computed, type ReadonlySignal, signal } from "@preact/signals-core";
import { loadSettings } from "./storage.js";

const defaults = {
  mode: {
    accelerated: false,
    accelerationFactor: 1,
  },

  prism: {
    size: 90,
    gray: 248,
    blueTint: 160,
    glowWidth: 7,
    glowFalloff: 3, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
  },

  rainbow: {
    spread: 50,
    handGlowWidth: 1,
    handGlowFalloff: 3, // 0=Linear, 1=Quadratic, 2=Cubic, 3=Exponential
    palette: 0, // 0=OkLCH Balanced, 1=Spectral, 2=Spectra6
  },

  effects: {
    grainIntensity: 100,
  },

  dither: {
    enabled: false,
    paletteId: 2, // 0 = IDEAL, 1 = SPECTRA6_INKY, 2 = SPECTRA6_EPDOPT
    strength: 98, // 0-100, maps to 0.0-1.0
    chromaEmphasis: 33, // 0-100, maps to 0.0-1.0
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
  hour: signal(
    persistedLive
      ? initialTime.getHours() % 12
      : (settings.timeHour ?? initialTime.getHours() % 12),
  ),
  minute: signal(
    persistedLive ? initialTime.getMinutes() : (settings.timeMinute ?? initialTime.getMinutes()),
  ),
  second: signal(initialTime.getSeconds()), // Used internally for animation

  // Actions
  setHour(e: Event): void {
    time.hour.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setMinute(e: Event): void {
    time.minute.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setNow(): void {
    const currentTime = new Date();

    batch(() => {
      time.hour.value = currentTime.getHours() % 12;
      time.minute.value = currentTime.getMinutes();
      time.second.value = currentTime.getSeconds();
    });
  },
};

export const prism = {
  // Signals: geometry
  size: signal(settings.prismSize ?? defaults.prism.size),

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
  // Signals: spread
  spread: signal(settings.rainbowSpread ?? defaults.rainbow.spread),

  // Signals: glow
  handGlowWidth: signal(settings.rainbowHandGlowWidth ?? defaults.rainbow.handGlowWidth),
  handGlowFalloff: signal(settings.rainbowHandGlowFalloff ?? defaults.rainbow.handGlowFalloff),

  // Signals: rendering mode
  palette: signal(settings.rainbowPalette ?? defaults.rainbow.palette),

  // Actions
  setSpread(e: Event): void {
    rainbow.spread.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setHandGlowWidth(e: Event): void {
    rainbow.handGlowWidth.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setHandGlowFalloff(e: Event): void {
    rainbow.handGlowFalloff.value = parseInt((e.target as HTMLSelectElement).value, 10);
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
  paletteId: signal(settings.ditherPaletteId ?? defaults.dither.paletteId),
  strength: signal(settings.ditherStrength ?? defaults.dither.strength),
  chromaEmphasis: signal(settings.ditherChromaEmphasis ?? defaults.dither.chromaEmphasis),

  // Actions
  toggleEnabled(): void {
    dither.enabled.value = !dither.enabled.value;
  },

  setPaletteId(e: Event): void {
    dither.paletteId.value = parseInt((e.target as HTMLSelectElement).value, 10);
  },

  setStrength(e: Event): void {
    dither.strength.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setChromaEmphasis(e: Event): void {
    dither.chromaEmphasis.value = parseInt((e.target as HTMLInputElement).value, 10);
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
      prism.gray.value = defaults.prism.gray;
      prism.blueTint.value = defaults.prism.blueTint;
      prism.glowWidth.value = defaults.prism.glowWidth;
      prism.glowFalloff.value = defaults.prism.glowFalloff;

      // Rainbow
      rainbow.spread.value = defaults.rainbow.spread;
      rainbow.handGlowWidth.value = defaults.rainbow.handGlowWidth;
      rainbow.handGlowFalloff.value = defaults.rainbow.handGlowFalloff;
      rainbow.palette.value = defaults.rainbow.palette;

      // Effects
      effects.grainIntensity.value = defaults.effects.grainIntensity;

      // Dither
      dither.enabled.value = defaults.dither.enabled;
      dither.paletteId.value = defaults.dither.paletteId;
      dither.strength.value = defaults.dither.strength;
      dither.chromaEmphasis.value = defaults.dither.chromaEmphasis;

      // Display
      display.highDpi.value = defaults.display.highDpi;
    });
  },
};
