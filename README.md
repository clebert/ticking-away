# Ticking Away

> [Ticking away the moments that make up a dull day.][time-song]

[time-song]: https://en.wikipedia.org/wiki/Time_(Pink_Floyd_song)

<img src="logo.png" alt="Ticking Away" width="512">

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Targets

- **[Web demo](https://clebert.github.io/ticking-away/)** — runs in the browser via WebAssembly; try
  different settings and preview the watchface.
- **[Pebble Round 2](https://repebble.com/watch)** — smartwatch (planned)

## Concept

The minute hand acts as a **light source** firing a white ray toward the watch center. The ray
enters a prism and disperses into a rainbow that targets the **hour hand position**. This creates a
clock where time is displayed through the direction of light rays rather than traditional hands.

## PNG Export

Build and run the PNG export binary to render the watchface to a PNG file:

```bash
zig build png -Doptimize=ReleaseFast
zig-out/bin/png <size> <hour> <minute> <output.png> [--grain | --dither]
```

- `size`: image size in pixels (square, diameter of the unit circle)
- `hour`: hour (0-23)
- `minute`: minute (0-59)
- `output.png`: output file path
- `--grain`: add film grain to the full-colour output
- `--dither`: quantize the output to the Pebble 64-colour cube

`--grain` and `--dither` are mutually exclusive; without either, no texture is applied.

```bash
zig build png -Doptimize=ReleaseFast && \
zig-out/bin/png 1024 7 14 logo.png --grain
```
