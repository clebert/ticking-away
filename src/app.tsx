import type { JSX } from "preact";
import { render as preactRender } from "preact";
import { AnimationProvider } from "./animation.tsx";
import { ConfigProvider } from "./config.tsx";
import { Controls } from "./controls.tsx";
import { useRenderer } from "./renderer.ts";
import { SettingsProvider } from "./settings.tsx";
import { initWasm } from "./wasm.ts";

const isFullscreen = new URLSearchParams(window.location.search).has("fullscreen");

function FullscreenContent(): JSX.Element {
  useRenderer();

  return (
    <a id="canvas-container" class="fullscreen" href={window.location.pathname}>
      <canvas id="canvas" />
    </a>
  );
}

function AppContent(): JSX.Element {
  useRenderer();

  const fullscreenUrl = `${window.location.pathname}?fullscreen`;

  return (
    <>
      <header>
        <h1>Ticking Away</h1>
        <span class="subtitle">the moments that make up a dull day.</span>
        <a href={fullscreenUrl} class="fullscreen-link">
          Fullscreen
        </a>
      </header>

      <main>
        <a id="canvas-container" href={fullscreenUrl}>
          <canvas id="canvas" />
        </a>
        <aside id="controls">
          <Controls />
        </aside>
      </main>
    </>
  );
}

function App(): JSX.Element {
  return (
    <SettingsProvider>
      <ConfigProvider>
        <AnimationProvider>
          {isFullscreen ? <FullscreenContent /> : <AppContent />}
        </AnimationProvider>
      </ConfigProvider>
    </SettingsProvider>
  );
}

initWasm().then(() => {
  preactRender(<App />, document.body);
});
