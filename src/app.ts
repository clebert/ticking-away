import { batch, effect } from "@preact/signals-core";
import { startAnimation, stopAnimation } from "./animation.ts";
import { createBinder } from "./binder.ts";
import { resizeCanvas } from "./canvas.ts";
import { render } from "./renderer.ts";
import { saveSettings } from "./storage.ts";
import * as stores from "./stores.ts";
import { initWasm } from "./wasm.ts";

initWasm().then(() => {
  createBinder({ stores })(document.body);

  window.addEventListener("resize", () => {
    resizeCanvas(stores.display.pebble.value);
    render();
  });

  effect(render);
  effect(() => saveSettings(stores));
  effect(() => resizeCanvas(stores.display.pebble.value));

  effect(() => {
    stopAnimation();

    if (stores.mode.live.value) {
      startAnimation(stores.mode.accelerated.value, stores.mode.accelerationFactor.value);
    }
  });

  effect(() => {
    if (!stores.mode.live.value) {
      batch(() => {
        stores.time.minutes.value = Math.round(stores.time.minutes.value) % 60;
        stores.time.seconds.value = Math.round(stores.time.seconds.value) % 60;
      });
    }
  });
});
