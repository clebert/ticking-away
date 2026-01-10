# Ticking Away

> _Ticking away the moments that make up a dull day._

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow. The name comes from the opening line of "Time".

## Concept

The minute hand acts as a **light source** firing a white ray toward the watch center. The ray
enters a prism and disperses into a rainbow that targets the **hour hand position**. This creates a
clock where time is displayed through the direction of light rays rather than traditional hands.

## Requirements

### Core Behavior

- **Minute = Light Source**: Ray originates from minute position on the watch edge, directed toward
  center
- **Hour = Target**: Rainbow converges on the hour position
- **Dynamic Hour**: Hour position interpolates smoothly based on minute progress (like a real analog
  clock)

### Visual Design

- White entry ray visible from minute position to prism
- Artistic white-to-gray gradient inside prism (mimics album cover aesthetic)
- Rainbow colors appear only after exiting the prism
- Correct spectral order: red bends least, violet bends most

### Constraints

- **No physics simulation**: Skip Snell's law and real Cauchy dispersion values
- **Prism**: Apex up, 60-degree apex angle, no rotation control
- **Fast math**: Target is resource-constrained devices
- **C for rendering**: All math and rendering in C/WASM, TypeScript only for UI
