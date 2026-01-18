# Ticking Away

> _Ticking away the moments that make up a dull day._

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow. The name comes from the opening line of "Time".

## Concept

The minute hand acts as a **light source** firing a white ray toward the watch center. The ray
enters a prism and disperses into a rainbow that targets the **hour hand position**. This creates a
clock where time is displayed through the direction of light rays rather than traditional hands.

## Features

### Time Display

- **Minute = Light Source**: Ray originates from minute position on the watch edge
- **Hour = Target**: Rainbow converges on the hour position (interpolates smoothly like an analog
  clock)
- **Seconds Sparkle**: A sparkle travels around the prism edge to indicate seconds

### Visual Design

- White entry ray from minute position to prism
- Internal rays use additive blending for natural color overlap effects
- Rainbow colors appear after exiting the prism
- Correct spectral order: red bends least, violet bends most
- 12 hour markers always visible around the edge

### Modes & Settings

- **Live Mode**: Real-time clock display with optional accelerated time
- **Fullscreen Mode**: Available in live mode for distraction-free viewing
- **Show Markers**: Toggle hour markers visibility
- **Pebble Mode**: Fixed 260×260 size for smartwatch preview
- **1-Bit Dithering**: Applies Atkinson dithering for a retro monochrome look

## Architecture

The project uses a pure software renderer via WASM:

- C code in [graphics.h](src/graphics.h) writes directly to an RGBA framebuffer
- TypeScript reads this buffer and uses `putImageData()` to display on an HTML5 Canvas
- All rendering is per-pixel: additive blending for light rays, alpha blending for overlays
