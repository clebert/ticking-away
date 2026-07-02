# Ticking Away

[...the moments that make up a dull day.][time-song]

[time-song]: https://en.wikipedia.org/wiki/Time_(Pink_Floyd_song)

<img src="logo.png" alt="Ticking Away" width="512">

A watchface inspired by Pink Floyd's "Dark Side of the Moon" album cover, featuring a prism that
refracts light into a rainbow.

## Targets

- **[Web demo](https://clebert.github.io/ticking-away/)** — runs in the browser via WebAssembly; try
  different settings and preview the watchface.
- **[Pebble Round 2](https://repebble.com/watch)** — smartwatch (`gabbro`, 260×260); see
  [Pebble Watchface](#pebble-watchface)
- **[TRMNL OG](https://usetrmnl.com/)** — 7.5″ 800×480 e-ink display driven bare-metal on an
  ESP32-C3; see [TRMNL Watchface](#trmnl-watchface)

## Concept

The minute hand acts as a **light source** firing a white ray toward the watch center. The ray
enters a prism and disperses into a rainbow that targets the **hour hand position**. This creates a
clock where time is displayed through the direction of light rays rather than traditional hands.

## PNG Export

Build and run the PNG export binary to render the watchface to a PNG file:

```bash
zig build png -Doptimize=ReleaseFast
zig-out/bin/png <size> <hour> <minute> <output.png> [--grain | --dither-pebble | --dither-trmnl] [--sharp]
```

- `size`: image size in pixels (square, diameter of the unit circle)
- `hour`: hour (0-23)
- `minute`: minute (0-59)
- `output.png`: output file path
- `--grain`: add film grain to the full-colour output
- `--dither-pebble`: quantize the output to the Pebble 64-colour cube (Floyd–Steinberg)
- `--dither-trmnl`: quantize the output to the TRMNL e-ink four greyscale levels (Floyd–Steinberg)
- `--sharp`: album-cover look — no glow, solid rainbow bands, and crisp rays

Edges are antialiased analytically (per-pixel coverage), so no supersampling flag is needed.

The texture flags are mutually exclusive; without any, no texture is applied.

```bash
zig build png -Doptimize=ReleaseFast && \
zig-out/bin/png 1024 7 14 logo.png --grain
```

```bash
zig build png -Doptimize=ReleaseFast && \
zig-out/bin/png 260 7 14 pebble.png --dither-pebble
```

```bash
zig build png -Doptimize=ReleaseFast && \
zig-out/bin/png 1964 7 14 wallpaper-14-inch.png --grain
```

```bash
zig build png -Doptimize=ReleaseFast && \
zig-out/bin/png 2234 7 14 wallpaper-16-inch.png --grain
```

## Pebble Watchface

The watchface also runs on the **Pebble Round 2** (`gabbro`, 260×260). The Zig render core in `lib/`
is cross-compiled to a freestanding Thumb static library and linked into a thin C app shell under
[`bin/pebble`](bin/pebble).

Install the Pebble SDK once — it provides the `pebble` CLI, the arm-none-eabi toolchain, and the
QEMU emulator:

```bash
uv tool install pebble-tool --python 3.13
pebble sdk install latest
```

Then cross-compile the render core, link the `.pbw`, and run it in the emulator:

```bash
zig build pebble-lib              # cross-compile bin/pebble/libwatchface.a
cd bin/pebble
pebble clean && pebble build      # clean first so waf relinks the current library
pebble install --emulator gabbro  # boot QEMU and install; re-run if the first
                                  # call times out while the firmware boots
pebble screenshot watchface.png   # capture after the face has painted
```

## TRMNL Watchface

The watchface also runs on the **[TRMNL OG](https://usetrmnl.com/)** — a 7.5″ 800×480 UC8179 e-ink
panel driven by an ESP32-C3. The Zig render core in `lib/` is cross-compiled to a bare-metal RV32IMC
firmware under [`bin/trmnl`](bin/trmnl) that bit-bangs the panel directly: no ESP-IDF, no
second-stage bootloader. The prism and rainbow are dithered to the panel's four greyscale levels
with the same Floyd–Steinberg core the Pebble target uses.

The image is RAM-resident — a custom linker script lays it entirely into SRAM, and the ESP32-C3 ROM
first-stage loader copies it in and jumps to the entry point (Espressif "Simple Boot"), so the flash
holds nothing but the raw image at offset `0x0`.

Flashing uses **[espflash](https://github.com/esp-rs/espflash)**:

```bash
brew install espflash
```

### Enter download mode

The TRMNL has two controls: a power slide switch and a circular **boot button** below it. The
ESP32-C3 has no auto-reset wired to USB, so download mode is entered by hand:

1. Plug a data USB-C cable into the TRMNL — it enumerates as `/dev/cu.usbmodem*`, the ESP32-C3's
   native USB-Serial-JTAG (no driver, no external adapter).
2. Slide the power switch **off**.
3. **Hold the boot button** while sliding the switch **on**, then release.

Confirm it is listening with `espflash list-ports` (look for an "Espressif USB JTAG/serial debug
unit"). Re-run this sequence before each flash: once the firmware's render loop takes over the chip
leaves download mode.

### Build and flash

The image is bare-metal (not an ESP-IDF app) and is reached without a reset, so every device-facing
espflash call needs `--before no-reset` (talk to the manually-entered ROM loader, don't toggle
DTR/RTS) and `--ignore-app-descriptor` (skip the ESP-IDF app-header check):

```bash
zig build trmnl                                                   # build zig-out/bin/trmnl

# Run once from RAM — volatile, reverts to the stock firmware on reset (best for iterating):
espflash flash --chip esp32c3 --ram --no-stub --before no-reset --after no-reset \
  --ignore-app-descriptor zig-out/bin/trmnl

# Or install persistently to flash offset 0x0 (no bootloader, no partition table), then power-cycle:
espflash save-image --chip esp32c3 --ignore-app-descriptor zig-out/bin/trmnl zig-out/bin/trmnl.bin
espflash write-bin --chip esp32c3 --before no-reset 0x0 zig-out/bin/trmnl.bin
```

A full e-ink refresh takes a few seconds; the firmware renders the built-in 7:14 frame once, then
holds it on screen with no power. Writing to flash overwrites the stock firmware — restore it any
time via [trmnl.com/flash](https://trmnl.com/flash).
