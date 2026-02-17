# Raspberry Pi Pico 2 Setup

Setup guide for running the watchface on a Raspberry Pi Pico 2 with an Inky Impression display.

## Hardware

- Raspberry Pi Pico 2 (RP2350)
- Waveshare Pico-To-HAT adapter (routes Pico GP pins to 40-pin header)
- Inky Impression 13.3" (Spectra 6, 1600x1200, 6-color)
- 4x AA NiMH batteries (4.8V, 2000 mAh) with micro-USB battery box

## Assembly

1. Solder headers onto the Pico 2 (if not pre-soldered)
2. Insert the Pico 2 into the Waveshare Pico-To-HAT adapter
3. Connect the Inky Impression 13.3" to the 40-pin header on the adapter
4. Connect the battery box to the Pico 2's micro-USB port

## Pin Mapping

The Waveshare Pico-To-HAT routes Pico GP pins to the 40-pin header. MOSI and SCLK land on the Pico's
SPI1 peripheral.

| Function | Physical Pin | BCM Pin | Pico GP | SPI1 Function |
| -------- | ------------ | ------- | ------- | ------------- |
| RESET    | 13           | 27      | GP27    | GPIO          |
| BUSY     | 11           | 17      | GP17    | GPIO (input)  |
| DC       | 15           | 22      | GP22    | GPIO          |
| CS0      | 37           | 26      | GP26    | GPIO          |
| CS1      | 36           | 16      | GP16    | GPIO          |
| MOSI     | 19           | 10      | GP11    | SPI1 TX       |
| SCLK     | 23           | 11      | GP10    | SPI1 SCK      |

## Setting the Initial Time

The Pico 2 has no battery-backed RTC. The initial time and UTC offset are both captured
automatically at build time from the host system clock and `/etc/localtime`. Just build and flash
promptly.

After the initial flash, the always-on (AON) timer preserves time across wake cycles. Time is only
lost on full power removal.

## Build

```sh
zig build inky-pico -Doptimize=ReleaseFast
```

Output: `zig-out/inky-pico.uf2`

## Flash

1. Hold the BOOTSEL button on the Pico 2
2. Connect the Pico 2 to your computer via USB
3. Release the BOOTSEL button (a USB drive named "RP2350" appears)
4. Drag `zig-out/inky-pico.uf2` onto the drive
5. The Pico 2 reboots and starts running automatically

## Expected Behavior

After flashing, the Pico 2 will:

1. Render the watchface (~5s at 150 MHz)
2. Stream it to the display over SPI (~5s)
3. Trigger the display refresh (~30-40s physical e-ink update)
4. Set an alarm for 5 minutes
5. Enter dormant mode (~1 mA board current)
6. Wake on alarm and repeat

Estimated battery life with 2000 mAh NiMH cells: ~8 days at 5-minute intervals.
