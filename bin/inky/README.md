# Inky Display Binary

Renders the watchface for the
[Inky Impression 13.3"](https://shop.pimoroni.com/products/inky-impression-13-3) Spectra 6 e-ink
display (1600x1200, 6-color).

## Mission

### Phase 1: Pi Zero W2

Run natively on a Raspberry Pi Zero W2 driving the display over SPI. The rendering pipeline uses
Pico 2-compatible budgets: 1-row bands, ~53 KB working set, two-pass CS0/CS1 splitting. Packed rows
are streamed directly to the display controller as each band is rendered — no full-frame buffer
needed.

### Phase 2: Pico 2

Run on a Raspberry Pi Pico 2 (RP2350, 520 KB SRAM). Same rendering pipeline and streaming approach,
different SPI stack (RP2350 hardware SPI instead of Linux spidev).

## Current State

Native binary that drives the display over SPI in a clock loop.

- Reads system time, snaps to configurable interval boundaries
- Renders in the rotated display orientation (1200x1600) using a rotated viewport
- Uses 1-pixel-height bands to match Pico 2 memory constraints (~53 KB working set)
- Streams packed rows directly to the display controller over SPI (CS0 then CS1)
- Triggers e-ink refresh (~12s), then sleeps until the next interval boundary

```
zig build inky -Doptimize=ReleaseFast && \
zig-out/bin/inky [--interval <minutes>]
```

The interval must evenly divide 60 (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60). Default: 1.
