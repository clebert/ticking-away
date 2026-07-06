import type { JSX, TargetedEvent } from "preact";
import { useAnimation } from "./animation.tsx";
import { type Config, resetConfig, useConfig } from "./config.tsx";
import { resetSettings, useSettings } from "./settings.tsx";

function integerValue(event: TargetedEvent<HTMLInputElement | HTMLSelectElement>): number {
  return parseInt(event.currentTarget.value, 10);
}

function textureValue(event: TargetedEvent<HTMLSelectElement>): Config["texture"] {
  const value = event.currentTarget.value;

  switch (value) {
    case "none":
    case "grain":
    case "dither_pebble":
    case "dither_trmnl":
      return value;
    default:
      throw new Error(`Unexpected texture: ${value}`);
  }
}

function rainbowStyleValue(event: TargetedEvent<HTMLSelectElement>): Config["rainbow_style"] {
  const value = event.currentTarget.value;

  switch (value) {
    case "dark_side_of_the_moon":
    case "vivid":
    case "spectrum":
      return value;
    default:
      throw new Error(`Unexpected rainbow style: ${value}`);
  }
}

function ModeSection(): JSX.Element {
  const { settingsSignal, updateSettings } = useSettings();
  const { framesPerSecondSignal } = useAnimation();
  const { mode_live, mode_accelerated, mode_speed } = settingsSignal.value;

  return (
    <>
      <div class="section-title">Mode</div>
      <div class="control-group">
        <label>
          <input
            type="checkbox"
            checked={mode_live}
            onChange={() => updateSettings("mode_live", !mode_live)}
          />{" "}
          Live
          {mode_live && framesPerSecondSignal.value > 0 && (
            <span class="fps">{framesPerSecondSignal.value} fps</span>
          )}
        </label>
      </div>
      <div class="control-group">
        <label>
          <input
            type="checkbox"
            checked={mode_accelerated}
            onChange={() => updateSettings("mode_accelerated", !mode_accelerated)}
          />{" "}
          Accelerated
        </label>
      </div>
      <div class="control-group">
        <label>Speed</label>
        <select
          value={mode_speed}
          onChange={(event) => updateSettings("mode_speed", integerValue(event))}
          disabled={!mode_accelerated}
        >
          <option value="1">1 min/sec</option>
          <option value="10">10 min/sec</option>
          <option value="30">30 min/sec</option>
          <option value="60">1 hour/sec</option>
          <option value="120">2 hours/sec</option>
        </select>
      </div>
    </>
  );
}

function TimeSection(): JSX.Element | null {
  const { settingsSignal } = useSettings();
  const { mode_live } = settingsSignal.value;
  const { hourSignal, minuteSignal } = useAnimation();

  if (mode_live) return null;

  return (
    <>
      <div class="section-title">Time</div>
      <div class="control-group">
        <label>
          Hour: <span>{hourSignal.value}</span>
        </label>
        <input
          type="range"
          min="0"
          max="11"
          value={hourSignal.value}
          onInput={(event) => {
            hourSignal.value = integerValue(event);
          }}
        />
      </div>
      <div class="control-group">
        <label>
          Minute: <span>{minuteSignal.value}</span>
        </label>
        <input
          type="range"
          min="0"
          max="59"
          value={minuteSignal.value}
          onInput={(event) => {
            minuteSignal.value = integerValue(event);
          }}
        />
      </div>
      <div class="button-row">
        <button
          type="button"
          class="action-button"
          onClick={() => {
            const now = new Date();
            hourSignal.value = now.getHours() % 12;
            minuteSignal.value = now.getMinutes();
          }}
        >
          Set to Now
        </button>
      </div>
    </>
  );
}

function PrismSection(): JSX.Element {
  const { configSignal, updateConfig } = useConfig();
  const config = configSignal.value;

  return (
    <>
      <div class="section-title">Prism</div>
      <div class="control-group">
        <label>
          Size: <span>{Math.round(config.prism_normalized_size * 100)}</span>%
        </label>
        <input
          type="range"
          min="10"
          max="100"
          value={Math.round(config.prism_normalized_size * 100)}
          onInput={(event) => updateConfig("prism_normalized_size", integerValue(event) / 100)}
        />
      </div>
      <div class="control-group">
        <label>
          Glow Width: <span>{Math.round(config.prism_glow_normalized_width * 100)}</span>%
        </label>
        <input
          type="range"
          min="0"
          max="50"
          value={Math.round(config.prism_glow_normalized_width * 100)}
          onInput={(event) =>
            updateConfig("prism_glow_normalized_width", integerValue(event) / 100)
          }
        />
      </div>
    </>
  );
}

function RainbowSection(): JSX.Element {
  const { configSignal, updateConfig } = useConfig();
  const config = configSignal.value;

  return (
    <>
      <div class="section-title">Rainbow</div>
      <div class="control-group">
        <label>Style</label>
        <select
          value={config.rainbow_style}
          onChange={(event) => updateConfig("rainbow_style", rainbowStyleValue(event))}
        >
          <option value="dark_side_of_the_moon">Dark Side of the Moon</option>
          <option value="vivid">Vivid</option>
          <option value="spectrum">Spectrum (wavelength)</option>
        </select>
      </div>
      <div class="control-group">
        <label>
          Spread: <span>{Math.round(config.rainbow_normalized_spread * 100)}</span>%
        </label>
        <input
          type="range"
          min="0"
          max="100"
          value={Math.round(config.rainbow_normalized_spread * 100)}
          onInput={(event) => updateConfig("rainbow_normalized_spread", integerValue(event) / 100)}
        />
      </div>
      <div class="control-group">
        <label>
          Hand Glow Width: <span>{(config.hand_glow_normalized_width * 100).toFixed(1)}</span>%
        </label>
        <input
          type="range"
          min="0"
          max="20"
          value={Math.round(config.hand_glow_normalized_width * 1000)}
          onInput={(event) =>
            updateConfig("hand_glow_normalized_width", integerValue(event) / 1000)
          }
        />
      </div>
    </>
  );
}

function EffectsSection(): JSX.Element {
  const { configSignal, updateConfig } = useConfig();
  const config = configSignal.value;

  return (
    <>
      <div class="section-title">Effects</div>
      <div class="control-group">
        <label>
          <input
            type="checkbox"
            checked={config.background_enabled}
            onChange={() => updateConfig("background_enabled", !config.background_enabled)}
          />{" "}
          Show Background
        </label>
      </div>
      <div class="control-group">
        <label>Texture</label>
        <select
          value={config.texture}
          onChange={(event) => updateConfig("texture", textureValue(event))}
        >
          <option value="none">None</option>
          <option value="grain">Grain</option>
          <option value="dither_pebble">Dither (Pebble)</option>
          <option value="dither_trmnl">Dither (TRMNL)</option>
        </select>
      </div>
      {config.texture === "grain" && (
        <div class="control-group">
          <label>
            Grain: <span>{Math.round(config.grain_normalized_deviation * 100)}</span>%
          </label>
          <input
            type="range"
            min="0"
            max="100"
            value={Math.round(config.grain_normalized_deviation * 100)}
            onInput={(event) =>
              updateConfig("grain_normalized_deviation", integerValue(event) / 100)
            }
          />
        </div>
      )}
    </>
  );
}

function ResetSection(): JSX.Element {
  const { settingsSignal } = useSettings();
  const { configSignal } = useConfig();

  return (
    <>
      <div class="section-title">Reset</div>
      <div class="button-row">
        <button
          type="button"
          class="action-button secondary"
          onClick={() => {
            resetSettings(settingsSignal);
            resetConfig(configSignal);
          }}
        >
          Reset All to Defaults
        </button>
      </div>
    </>
  );
}

export function Controls(): JSX.Element {
  return (
    <div class="control-panel">
      <ModeSection />
      <TimeSection />
      <PrismSection />
      <RainbowSection />
      <EffectsSection />
      <ResetSection />
    </div>
  );
}
