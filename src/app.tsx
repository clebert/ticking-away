import type { JSX } from "preact";
import { render as preactRender } from "preact";
import { AnimationProvider } from "./animation.tsx";
import { ConfigProvider } from "./config.tsx";
import { Controls } from "./controls.tsx";
import { useRenderer } from "./renderer.ts";
import { SettingsProvider } from "./settings.tsx";
import { initWasm } from "./wasm.ts";

function AppContent(): JSX.Element {
  useRenderer();

  return (
    <>
      <header>
        <h1>Ticking Away</h1>
        <span class="subtitle">the moments that make up a dull day.</span>
      </header>

      <main>
        <div id="canvas-container">
          <canvas id="canvas" />
        </div>
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
          <AppContent />
        </AnimationProvider>
      </ConfigProvider>
    </SettingsProvider>
  );
}

initWasm().then(() => {
  preactRender(<App />, document.body);
});
