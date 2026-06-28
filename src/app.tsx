import type { JSX } from "preact";
import { render as preactRender } from "preact";
import { AnimationProvider } from "./animation.tsx";
import { ConfigProvider } from "./config.tsx";
import { Controls } from "./controls.tsx";
import { useRenderer } from "./renderer.ts";
import { SettingsProvider } from "./settings.tsx";
import { initializeWebAssembly } from "./wasm.ts";

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
        <div class="brand">
          <svg class="prism" width="20" height="18" viewBox="0 0 20 18" aria-hidden="true">
            <path d="M10 1.4 L18.6 16.6 L1.4 16.6 Z" />
          </svg>
          <h1>Ticking Away</h1>
          <span class="subtitle">the moments that make up a dull day.</span>
        </div>
        <nav class="header-links">
          <a href="https://github.com/clebert/ticking-away">GitHub</a>
          <a href={fullscreenUrl}>Fullscreen</a>
        </nav>
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

initializeWebAssembly()
  .then(() => {
    preactRender(<App />, document.body);
  })
  .catch((error: unknown) => {
    document.body.textContent = `Failed to load watchface: ${error}`;
    console.error(error);
  });
