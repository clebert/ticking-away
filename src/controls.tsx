import type { JSX, TargetedEvent } from "preact";
import { useAnimation } from "./animation.tsx";
import { type Config, resetConfig, useConfig } from "./config.tsx";
import { resetSettings, useSettings } from "./settings.tsx";

function intValue(event: TargetedEvent<HTMLInputElement | HTMLSelectElement>): number {
  return parseInt(event.currentTarget.value, 10);
}

type StringKeys<T> = { [K in keyof T]: T[K] extends string ? K : never }[keyof T];

function selectValue<K extends StringKeys<Config>>(
  _key: K,
  event: TargetedEvent<HTMLSelectElement>,
): Config[K] {
  return event.currentTarget.value as Config[K];
}

function ModeSection(): JSX.Element {
  const { $settings, updateSettings } = useSettings();
  const { $fps } = useAnimation();
  const { mode_live, mode_accelerated, mode_speed } = $settings.value;

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
          {mode_live && $fps.value > 0 && <span class="fps">{$fps.value} fps</span>}
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
          onChange={(event) => updateSettings("mode_speed", intValue(event))}
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
  const { $settings } = useSettings();
  const { mode_live } = $settings.value;
  const { $hour, $minute } = useAnimation();

  if (mode_live) return null;

  return (
    <>
      <div class="section-title">Time</div>
      <div class="control-group">
        <label>
          Hour: <span>{$hour.value}</span>
        </label>
        <input
          type="range"
          min="0"
          max="11"
          value={$hour.value}
          onInput={(e) => {
            $hour.value = intValue(e);
          }}
        />
      </div>
      <div class="control-group">
        <label>
          Minute: <span>{$minute.value}</span>
        </label>
        <input
          type="range"
          min="0"
          max="59"
          value={$minute.value}
          onInput={(e) => {
            $minute.value = intValue(e);
          }}
        />
      </div>
      <div class="button-row">
        <button
          type="button"
          class="action-button"
          onClick={() => {
            const now = new Date();
            $hour.value = now.getHours() % 12;
            $minute.value = now.getMinutes();
          }}
        >
          Set to Now
        </button>
      </div>
    </>
  );
}

function PrismSection(): JSX.Element {
  const { $config, updateConfig } = useConfig();
  const config = $config.value;

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
          onInput={(e) => updateConfig("prism_normalized_size", intValue(e) / 100)}
        />
      </div>
      <div class="control-group">
        <label>
          Glow Green: <span>{Math.round(config.prism_glow_linear_green * 100)}</span>%
        </label>
        <input
          type="range"
          min="0"
          max="100"
          value={Math.round(config.prism_glow_linear_green * 100)}
          onInput={(e) => updateConfig("prism_glow_linear_green", intValue(e) / 100)}
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
          onInput={(e) => updateConfig("prism_glow_normalized_width", intValue(e) / 100)}
        />
      </div>
    </>
  );
}

function RainbowSection(): JSX.Element {
  const { $config, updateConfig } = useConfig();
  const config = $config.value;

  return (
    <>
      <div class="section-title">Rainbow</div>
      <div class="control-group">
        <label>
          Spread: <span>{Math.round(config.rainbow_normalized_spread * 100)}</span>%
        </label>
        <input
          type="range"
          min="0"
          max="100"
          value={Math.round(config.rainbow_normalized_spread * 100)}
          onInput={(e) => updateConfig("rainbow_normalized_spread", intValue(e) / 100)}
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
          onInput={(e) => updateConfig("hand_glow_normalized_width", intValue(e) / 1000)}
        />
      </div>
      <div class="control-group">
        <label>Color Palette</label>
        <select
          value={config.rainbow_palette_id}
          onChange={(e) => updateConfig("rainbow_palette_id", selectValue("rainbow_palette_id", e))}
        >
          <option value="oklch_balanced">OkLCH Balanced</option>
          <option value="spectral">Spectral</option>
        </select>
      </div>
    </>
  );
}

function EffectsSection(): JSX.Element {
  const { $config, updateConfig } = useConfig();
  const config = $config.value;

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
        <label>
          <input
            type="checkbox"
            checked={config.supersample_enabled}
            onChange={() => updateConfig("supersample_enabled", !config.supersample_enabled)}
          />{" "}
          Supersampling
        </label>
      </div>
      <div class="control-group">
        <label>Texture</label>
        <select
          value={config.texture}
          onChange={(e) => updateConfig("texture", selectValue("texture", e))}
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
            onInput={(e) => updateConfig("grain_normalized_deviation", intValue(e) / 100)}
          />
        </div>
      )}
    </>
  );
}

function ResetSection(): JSX.Element {
  const { $settings } = useSettings();
  const { $config } = useConfig();

  return (
    <>
      <div class="section-title">Reset</div>
      <div class="button-row">
        <button
          type="button"
          class="action-button secondary"
          onClick={() => {
            resetSettings($settings);
            resetConfig($config);
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
