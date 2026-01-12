import { createBinder, createStore } from "./statewire.js";

// =================================================================================================
// Constants
// =================================================================================================

const WATCH_WIDTH = 260;
const WATCH_HEIGHT = 260;
const STORAGE_KEY = "settings";

// =================================================================================================
// WASM Interface
// =================================================================================================

interface Wasm {
  render_watchface(
    fb: number,
    width: number,
    height: number,
    hour: number,
    minute: number,
    second: number,
    prism_size_percent: number,
    rainbow_spread: number,
    minimal_mode: number,
    prism_r: number,
    prism_g: number,
    prism_b: number,
    show_seconds: number,
    sparkle_size_percent: number,
    glow_width_percent: number,
    glow_intensity: number,
    glow_falloff: number,
    ray_glow_width_percent: number,
    ray_glow_intensity: number,
    ray_glow_falloff: number,
    internal_ray_real_colors: number,
    artistic_dispersion: number,
  ): void;
}

let wasmModule: Wasm | null = null;
let wasmMemory: WebAssembly.Memory | null = null;

async function initWasm(): Promise<void> {
  wasmMemory = new WebAssembly.Memory({ initial: 32, maximum: 1024 }); // 2MB initial, 64MB max

  const response = await fetch("/index.wasm");
  const bytes = await response.arrayBuffer();

  const result = await WebAssembly.instantiate(bytes, { env: { memory: wasmMemory } });

  wasmModule = result.instance.exports as unknown as Wasm;
}

// =================================================================================================
// State
// =================================================================================================

interface AppState {
  hours: number;
  minutes: number;
  seconds: number;
  prismSize: number; // 10-90 (%)
  rainbowSpread: number; // 0-100 (maps to 0.0-1.0)
  liveMode: boolean;
  fullscreen: boolean; // true = fullscreen mode active
  fullscreenHidden: boolean; // derived: !liveMode (only show when live)
  acceleratedTime: boolean; // true = use accelerationFactor, false = real time
  accelerationFactor: number; // minutes per second when accelerated
  accelerationHidden: boolean; // derived: !acceleratedTime (for hiding dropdown)
  pebbleMode: boolean;
  minimalMode: boolean;
  prismGray: number; // 0-255 gray value for prism stroke and internal rays
  prismBlueTint: number; // 0-50 blue tint amount (reduces red/green to create cool bluish gray)
  showSeconds: boolean; // true = show seconds sparkle on prism edge
  sparkleSize: number; // 100-1000 (% of default size)
  secondsDisabled: boolean; // derived: liveMode && acceleratedTime (disable toggle in accelerated live mode)
  glowWidth: number; // 5-50 (% of radius)
  glowIntensity: number; // 10-100 (%)
  glowFalloff: number; // 0=linear, 1=quadratic, 2=cubic, 3=exponential
  rayGlowWidth: number; // 0-10 (% of radius)
  rayGlowIntensity: number; // 0-100 (%)
  rayGlowFalloff: number; // 0=linear, 1=quadratic, 2=cubic, 3=exponential
  internalRayRealColors: boolean; // true = use wavelength-based colors for internal rays
  artisticDispersion: boolean; // true = artistic (red first at top), false = physical (violet bends most)
  wakeLockText: string;
  wakeLockClass: string;
}

interface PersistedSettings {
  prismSize: number;
  rainbowSpread: number;
  acceleratedTime: boolean;
  accelerationFactor: number;
  pebbleMode: boolean;
  minimalMode: boolean;
  prismGray: number;
  prismBlueTint: number;
  showSeconds: boolean;
  sparkleSize: number;
  glowWidth: number;
  glowIntensity: number;
  glowFalloff: number;
  rayGlowWidth: number;
  rayGlowIntensity: number;
  rayGlowFalloff: number;
  internalRayRealColors: boolean;
  artisticDispersion: boolean;
}

function loadSettings(): Partial<PersistedSettings> {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      return JSON.parse(stored) as PersistedSettings;
    }
  } catch {
    // Ignore localStorage errors
  }
  return {};
}

function saveSettings(state: AppState): void {
  try {
    const settings: PersistedSettings = {
      prismSize: state.prismSize,
      rainbowSpread: state.rainbowSpread,
      acceleratedTime: state.acceleratedTime,
      accelerationFactor: state.accelerationFactor,
      pebbleMode: state.pebbleMode,
      minimalMode: state.minimalMode,
      prismGray: state.prismGray,
      prismBlueTint: state.prismBlueTint,
      showSeconds: state.showSeconds,
      sparkleSize: state.sparkleSize,
      glowWidth: state.glowWidth,
      glowIntensity: state.glowIntensity,
      glowFalloff: state.glowFalloff,
      rayGlowWidth: state.rayGlowWidth,
      rayGlowIntensity: state.rayGlowIntensity,
      rayGlowFalloff: state.rayGlowFalloff,
      internalRayRealColors: state.internalRayRealColors,
      artisticDispersion: state.artisticDispersion,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  } catch {
    // Ignore localStorage errors
  }
}

const now = new Date();
const savedSettings = loadSettings();

const defaultState: AppState = {
  hours: now.getHours() % 12,
  minutes: now.getMinutes(),
  seconds: now.getSeconds(),
  prismSize: savedSettings.prismSize ?? 90,
  rainbowSpread: savedSettings.rainbowSpread ?? 30,
  liveMode: true,
  fullscreen: false,
  fullscreenHidden: false, // derived: !liveMode
  acceleratedTime: savedSettings.acceleratedTime ?? false,
  accelerationFactor: savedSettings.accelerationFactor ?? 1,
  accelerationHidden: !(savedSettings.acceleratedTime ?? false),
  pebbleMode: savedSettings.pebbleMode ?? false,
  minimalMode: savedSettings.minimalMode ?? true,
  prismGray: savedSettings.prismGray ?? 120,
  prismBlueTint: savedSettings.prismBlueTint ?? 50,
  showSeconds: savedSettings.showSeconds ?? true,
  sparkleSize: savedSettings.sparkleSize ?? 300,
  secondsDisabled: savedSettings.acceleratedTime ?? false, // derived: liveMode && acceleratedTime
  glowWidth: savedSettings.glowWidth ?? 20,
  glowIntensity: savedSettings.glowIntensity ?? 100,
  glowFalloff: savedSettings.glowFalloff ?? 3, // exponential by default
  rayGlowWidth: savedSettings.rayGlowWidth ?? 2,
  rayGlowIntensity: savedSettings.rayGlowIntensity ?? 100,
  rayGlowFalloff: savedSettings.rayGlowFalloff ?? 1, // quadratic by default
  internalRayRealColors: savedSettings.internalRayRealColors ?? true,
  artisticDispersion: savedSettings.artisticDispersion ?? true,
  wakeLockText: "",
  wakeLockClass: "",
};

// =================================================================================================
// Globals
// =================================================================================================

let canvas: HTMLCanvasElement;
let ctx: CanvasRenderingContext2D;
let fbDataPtr = 0;
let store: ReturnType<typeof createStore<AppState>>;
let liveAnimationFrame: number | null = null;
let acceleratedStartTime = 0;
let acceleratedStartMinutes = 0;
let wakeLock: WakeLockSentinel | null = null;

function updateWakeLockState(active: boolean): void {
  store.publish((s) => ({
    ...s,
    wakeLockText: active ? "(screen stays awake)" : "(screen may dim)",
    wakeLockClass: active ? "active" : "inactive",
  }));
}

function startLiveAnimation(): void {
  const state = store.getState();

  if (state.acceleratedTime) {
    // Accelerated: advance N minutes per second (based on accelerationFactor), starting from current time
    acceleratedStartTime = performance.now();
    acceleratedStartMinutes = state.hours * 60 + state.minutes;
    const factor = state.accelerationFactor;

    const animate = (): void => {
      const elapsed = (performance.now() - acceleratedStartTime) / 1000; // seconds
      const totalMinutes = acceleratedStartMinutes + elapsed * factor; // N minutes per second
      const wrappedMinutes = totalMinutes % (12 * 60); // wrap at 12 hours
      const newHours = Math.floor(wrappedMinutes / 60);
      const newMinutes = wrappedMinutes % 60;
      // Seconds advance at 60x the minute rate (60 seconds per minute)
      const newSeconds = (newMinutes * 60) % 60;

      store.publish((s) => ({ ...s, hours: newHours, minutes: newMinutes, seconds: newSeconds }));
      render(store.getState());
      liveAnimationFrame = requestAnimationFrame(animate);
    };

    liveAnimationFrame = requestAnimationFrame(animate);
  } else {
    // Real time: sync to actual clock with fractional seconds for smooth animation
    const animate = (): void => {
      const now = new Date();
      const fractionalSeconds = now.getSeconds() + now.getMilliseconds() / 1000;
      const fractionalMinutes = now.getMinutes() + fractionalSeconds / 60;

      store.publish((s) => ({
        ...s,
        hours: now.getHours() % 12,
        minutes: fractionalMinutes,
        seconds: fractionalSeconds,
      }));
      render(store.getState());
      liveAnimationFrame = requestAnimationFrame(animate);
    };

    liveAnimationFrame = requestAnimationFrame(animate);
  }
}

function stopLiveAnimation(): void {
  if (liveAnimationFrame !== null) {
    cancelAnimationFrame(liveAnimationFrame);
    liveAnimationFrame = null;
  }
}

// =================================================================================================
// Canvas Setup
// =================================================================================================

function resizeCanvas(pebbleMode: boolean): void {
  const container = canvas.parentElement as HTMLElement;
  const rect = container.getBoundingClientRect();

  let width: number;
  let height: number;

  if (pebbleMode) {
    width = WATCH_WIDTH;
    height = WATCH_HEIGHT;
    canvas.style.width = `${WATCH_WIDTH}px`;
    canvas.style.height = `${WATCH_HEIGHT}px`;
    canvas.style.position = "absolute";
    canvas.style.top = "50%";
    canvas.style.left = "50%";
    canvas.style.transform = "translate(-50%, -50%)";
    // Match the WASM background color (RGB 35,35,35) so canvas blends with container
    container.style.background = "#232323";
  } else {
    const dpr = window.devicePixelRatio || 1;
    width = Math.max(Math.floor(rect.width * dpr), 100);
    height = Math.max(Math.floor(rect.height * dpr), 100);
    // Keep canvas position absolute so it doesn't affect flex layout
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    canvas.style.position = "absolute";
    canvas.style.top = "0";
    canvas.style.left = "0";
    canvas.style.transform = "";
    container.style.background = "#000";
  }

  canvas.width = width;
  canvas.height = height;

  // Ensure memory is large enough.
  // WASM memory layout:
  //   0-66591:     stack space
  //   66592:       initial stack pointer
  //   1048576+:    framebuffer (1MB offset, safely above stack)
  const FB_OFFSET = 1048576; // 1MB
  if (wasmMemory) {
    const fbSize = width * height * 4;
    const neededBytes = FB_OFFSET + fbSize;
    const currentBytes = wasmMemory.buffer.byteLength;
    if (currentBytes < neededBytes) {
      const pagesToGrow = Math.ceil((neededBytes - currentBytes) / 65536);
      wasmMemory.grow(pagesToGrow);
    }
  }
  fbDataPtr = FB_OFFSET;
}

// =================================================================================================
// Rendering
// =================================================================================================

function render(state: AppState): void {
  if (!wasmModule || !wasmMemory) return;

  const width = canvas.width;
  const height = canvas.height;

  // Calculate prism RGB from gray + blue tint
  // Blue tint reduces red more than green, creating a cool bluish appearance
  const prismR = Math.max(0, state.prismGray - state.prismBlueTint);
  const prismG = Math.max(0, state.prismGray - Math.floor(state.prismBlueTint / 2));
  const prismB = state.prismGray;

  // Call WASM to render
  wasmModule.render_watchface(
    fbDataPtr,
    width,
    height,
    state.hours,
    state.minutes,
    state.seconds,
    state.prismSize,
    state.rainbowSpread / 100.0, // Convert 0-100 to 0.0-1.0
    state.minimalMode ? 1 : 0,
    prismR,
    prismG,
    prismB,
    state.showSeconds && !state.secondsDisabled ? 1 : 0,
    state.sparkleSize / 100.0, // Convert 100-1000 to 1.0-10.0
    state.glowWidth / 100.0, // Convert 5-50 to 0.05-0.50
    state.glowIntensity / 100.0, // Convert 10-100 to 0.1-1.0
    state.glowFalloff,
    state.rayGlowWidth / 100.0, // Convert 0-10 to 0.0-0.10
    state.rayGlowIntensity / 100.0, // Convert 0-100 to 0.0-1.0
    state.rayGlowFalloff,
    state.internalRayRealColors ? 1 : 0,
    state.artisticDispersion ? 1 : 0,
  );

  // Copy framebuffer to canvas
  const fbArray = new Uint8ClampedArray(wasmMemory.buffer, fbDataPtr, width * height * 4);
  const imageData = new ImageData(fbArray, width, height);
  ctx.putImageData(imageData, 0, 0);
}

// =================================================================================================
// Actions
// =================================================================================================

const actions = {
  setHours(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, hours: value }));
    render(store.getState());
  },

  setMinutes(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, minutes: value }));
    render(store.getState());
  },

  setSeconds(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, seconds: value }));
    render(store.getState());
  },

  setPrismSize(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, prismSize: value }));
    render(store.getState());
  },

  setRainbowSpread(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, rainbowSpread: value }));
    render(store.getState());
  },

  setNow(): void {
    const now = new Date();
    store.publish((s) => ({
      ...s,
      hours: now.getHours() % 12,
      minutes: now.getMinutes(),
      seconds: now.getSeconds(),
    }));
    render(store.getState());
  },

  async toggleLiveMode(): Promise<void> {
    const newLiveMode = !store.getState().liveMode;
    store.publish((s) => ({
      ...s,
      liveMode: newLiveMode,
      fullscreenHidden: !newLiveMode,
      secondsDisabled: newLiveMode && s.acceleratedTime,
    }));

    if (newLiveMode) {
      // Request wake lock to prevent screen dimming
      if ("wakeLock" in navigator) {
        try {
          wakeLock = await navigator.wakeLock.request("screen");
          wakeLock.addEventListener("release", () => {
            wakeLock = null;
            updateWakeLockState(false);
          });
        } catch {
          // Wake lock request failed (e.g., low battery, tab not visible)
        }
      }
      updateWakeLockState(wakeLock !== null);

      startLiveAnimation();
    } else {
      // Release wake lock
      if (wakeLock !== null) {
        await wakeLock.release();
        wakeLock = null;
      }
      updateWakeLockState(false);

      stopLiveAnimation();

      // Round minutes and seconds to nearest integer for the sliders
      store.publish((s) => ({
        ...s,
        minutes: Math.round(s.minutes) % 60,
        seconds: Math.round(s.seconds) % 60,
      }));
      render(store.getState());
    }
  },

  toggleAcceleratedTime(): void {
    store.publish((s) => {
      const newAcceleratedTime = !s.acceleratedTime;
      return {
        ...s,
        acceleratedTime: newAcceleratedTime,
        accelerationHidden: !newAcceleratedTime,
        secondsDisabled: s.liveMode && newAcceleratedTime,
      };
    });

    // Restart interval if live mode is active
    if (store.getState().liveMode) {
      stopLiveAnimation();
      startLiveAnimation();
    }
  },

  setAccelerationFactor(e: Event): void {
    const value = parseInt((e.target as HTMLSelectElement).value, 10);
    store.publish((s) => ({ ...s, accelerationFactor: value }));

    // Restart animation if live mode is active
    if (store.getState().liveMode) {
      stopLiveAnimation();
      startLiveAnimation();
    }
  },

  togglePebbleMode(): void {
    const newPebbleMode = !store.getState().pebbleMode;
    store.publish((s) => ({ ...s, pebbleMode: newPebbleMode }));
    resizeCanvas(newPebbleMode);
    render(store.getState());
  },

  toggleMinimalMode(): void {
    store.publish((s) => ({ ...s, minimalMode: !s.minimalMode }));
    render(store.getState());
  },

  toggleShowSeconds(): void {
    store.publish((s) => ({ ...s, showSeconds: !s.showSeconds }));
    render(store.getState());
  },

  setSparkleSize(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, sparkleSize: value }));
    render(store.getState());
  },

  async toggleFullscreen(): Promise<void> {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
    } else {
      await document.documentElement.requestFullscreen();
    }
  },

  setPrismGray(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, prismGray: value }));
    render(store.getState());
  },

  setPrismBlueTint(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, prismBlueTint: value }));
    render(store.getState());
  },

  setGlowWidth(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, glowWidth: value }));
    render(store.getState());
  },

  setGlowIntensity(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, glowIntensity: value }));
    render(store.getState());
  },

  setGlowFalloff(e: Event): void {
    const value = parseInt((e.target as HTMLSelectElement).value, 10);
    store.publish((s) => ({ ...s, glowFalloff: value }));
    render(store.getState());
  },

  setRayGlowWidth(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, rayGlowWidth: value }));
    render(store.getState());
  },

  setRayGlowIntensity(e: Event): void {
    const value = parseInt((e.target as HTMLInputElement).value, 10);
    store.publish((s) => ({ ...s, rayGlowIntensity: value }));
    render(store.getState());
  },

  setRayGlowFalloff(e: Event): void {
    const value = parseInt((e.target as HTMLSelectElement).value, 10);
    store.publish((s) => ({ ...s, rayGlowFalloff: value }));
    render(store.getState());
  },

  toggleInternalRayRealColors(): void {
    store.publish((s) => ({ ...s, internalRayRealColors: !s.internalRayRealColors }));
    render(store.getState());
  },

  toggleArtisticDispersion(): void {
    store.publish((s) => ({ ...s, artisticDispersion: !s.artisticDispersion }));
    render(store.getState());
  },
};

// =================================================================================================
// Initialization
// =================================================================================================

async function init(): Promise<void> {
  canvas = document.getElementById("canvas") as HTMLCanvasElement;
  ctx = canvas.getContext("2d") as CanvasRenderingContext2D;

  // Initialize WASM
  await initWasm();

  // Create store
  store = createStore(defaultState);

  // Persist settings on change
  store.subscribe(saveSettings);

  // Bind controls
  createBinder(store, actions)(document.body);

  // Initial setup
  resizeCanvas(store.getState().pebbleMode);
  render(store.getState());

  // Start live animation immediately
  startLiveAnimation();

  // Handle resize
  window.addEventListener("resize", () => {
    resizeCanvas(store.getState().pebbleMode);
    render(store.getState());
  });

  // Sync fullscreen state when user exits via ESC or other means
  document.addEventListener("fullscreenchange", () => {
    const isFullscreen = document.fullscreenElement !== null;
    store.publish((s) => ({ ...s, fullscreen: isFullscreen }));
  });
}

init();
