# Ticking Away

> _Ticking away the moments that make up a dull day._

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow. The name comes from the opening line of "Time".

## Concept

The minute hand acts as a **light source** firing a white ray toward the watch center. The ray
enters a prism and disperses into a rainbow that targets the **hour hand position**. This creates a
clock where time is displayed through the direction of light rays rather than traditional hands.

## PNG Export

Build and run the PNG export binary to render the watchface to a PNG file:

```bash
zig build png -Doptimize=ReleaseFast
zig-out/bin/png <height> <hour> <minute> <output.png>
```

- `height`: image size in pixels (square, diameter of the unit circle)
- `hour`: hour (0-23)
- `minute`: minute (0-59)
- `output.png`: output file path

```bash
zig build png -Doptimize=ReleaseFast && \
zig-out/bin/png 2234 7 14 prism.png
```
