import preact from "@preact/preset-vite";
import { defineConfig } from "vite";

export default defineConfig(({ command, isPreview }) => ({
  // GitHub Pages serves the app from a project subpath, so the build (and `vite
  // preview`, which serves that build) must root assets at /ticking-away/. The dev server
  // serves from the origin root, so it stays at /.
  base: command === "build" || isPreview ? "/ticking-away/" : "/",
  plugins: [preact()],
}));
