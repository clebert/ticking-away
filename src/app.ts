import { effect } from "@preact/signals-core";
import { startAnimation, stopAnimation } from "./animation.ts";
import { createBinder } from "./binder.ts";
import { resizeCanvas } from "./canvas.ts";
import { render } from "./renderer.ts";
import { saveSettings } from "./storage.ts";
import * as stores from "./stores.ts";
import { initWasm } from "./wasm.ts";
import { initZigWasm } from "./zig-wasm.ts";

Promise.all([initWasm(), initZigWasm()]).then(() => {
  createBinder({ stores })(document.body);

  window.addEventListener("resize", () => {
    resizeCanvas(stores.display.highDpi.value);

    render();
  });

  effect(render);
  effect(() => saveSettings(stores));
  effect(() => {
    // Track clockOnly to resize when sidebar visibility changes (fullscreen uses resize event)
    stores.mode.clockOnly.value;

    resizeCanvas(stores.display.highDpi.value);

    // Re-render after resize since effect(render) won't trigger from canvas size change
    render();
  });

  effect(() => {
    stopAnimation();

    if (stores.mode.live.value) {
      startAnimation(stores.mode.accelerated.value, stores.mode.accelerationFactor.value);
    }
  });

  effect(() => {
    if (!stores.mode.live.value) {
      stores.time.minutes.value = Math.round(stores.time.minutes.value) % 60;
    }
  });
});
