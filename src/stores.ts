import { batch, computed, type ReadonlySignal, signal } from "@preact/signals-core";
import { loadSettings } from "./storage.js";

const initialTime = new Date();
const settings = loadSettings();

export const mode = {
  // Signals: display mode
  fullscreen: ((): ReadonlySignal<boolean> => {
    const fullscreen = signal(document.fullscreenElement !== null);

    document.addEventListener("fullscreenchange", () => {
      fullscreen.value = document.fullscreenElement !== null;
    });

    return fullscreen;
  })(),

  clockOnly: signal(new URLSearchParams(window.location.search).has("clock")),

  // Signals: time behavior
  live: signal(true),
  accelerated: signal(settings.modeAccelerated ?? false),
  accelerationFactor: signal(settings.modeAccelerationFactor ?? 1),

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
  size: signal(settings.prismSize ?? 90),
  rainbowSpread: signal(settings.prismRainbowSpread ?? 30),

  // Signals: color
  gray: signal(settings.prismGray ?? 120),
  blueTint: signal(settings.prismBlueTint ?? 50),

  // Signals: glow
  glowWidth: signal(settings.prismGlowWidth ?? 20),
  glowIntensity: signal(settings.prismGlowIntensity ?? 100),
  glowFalloff: signal(settings.prismGlowFalloff ?? 3),

  // Signals: sparkle
  sparkleSize: signal(settings.prismSparkleSize ?? 300),

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
  glowWidth: signal(settings.raysGlowWidth ?? 2),
  glowIntensity: signal(settings.raysGlowIntensity ?? 100),
  glowFalloff: signal(settings.raysGlowFalloff ?? 1),

  // Signals: color
  innerSpectrum: signal(settings.raysInnerSpectrum ?? true),
  artisticDispersion: signal(settings.raysArtisticDispersion ?? false),

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

export const background = {
  // Signals: effect intensities
  grainIntensity: signal(settings.backgroundGrainIntensity ?? 80),
  vignetteIntensity: signal(settings.backgroundVignetteIntensity ?? 100),

  // Computed
  grainDisabled: computed((): boolean => display.pebble.value),
  vignetteDisabled: computed((): boolean => display.pebble.value),

  // Actions
  setGrainIntensity(e: Event): void {
    background.grainIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },

  setVignetteIntensity(e: Event): void {
    background.vignetteIntensity.value = parseInt((e.target as HTMLInputElement).value, 10);
  },
};

export const display = {
  // Signals
  markers: signal(settings.displayMarkers ?? true),
  seconds: signal(settings.displaySeconds ?? true),
  dithering: signal(settings.displayDithering ?? false),
  pebble: signal(settings.displayPebble ?? false),

  // Computed
  secondsDisabled: computed((): boolean => mode.live.value && mode.accelerated.value),

  // Actions
  toggleMarkers(): void {
    display.markers.value = !display.markers.value;
  },

  toggleSeconds(): void {
    display.seconds.value = !display.seconds.value;
  },

  toggleDithering(): void {
    display.dithering.value = !display.dithering.value;
  },

  togglePebble(): void {
    display.pebble.value = !display.pebble.value;
  },
};
