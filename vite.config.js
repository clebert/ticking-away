import preact from "@preact/preset-vite";
import { defineConfig } from "vite";

export default defineConfig(({ command }) => ({
  base: command === "build" ? "/ticking-away/" : "/",
  plugins: [preact()],
  server: { host: true, port: 4242, strictPort: true },
}));
