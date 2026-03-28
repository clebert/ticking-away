# Inky Impression 13.3" on Pico 2 — Debug Log

Debug session investigating why the CS1 (top half) controller does not respond.

---

## Setup

### Hardware

- **MCU:** Raspberry Pi Pico 2 (RP2350)
- **Display:** Inky Impression 13.3" (Spectra 6, dual EL133UF1 controllers)
- **Connection:** Direct jumper wires (no Waveshare adapter)
- **Debug probe:** Second Pico running debugprobe firmware, connected to GP0 (UART TX)

### Wiring (Pico 2 → Display 40-pin header)

| Pico GP | Pico Pin | Display Pin | BCM Equiv | Function |
| ------- | -------- | ----------- | --------- | -------- |
| GP0     | 1        | (Probe GP5) | --        | UART TX  |
| GP2     | 4        | 13          | 27        | RESET    |
| GP3     | 5        | (not wired) | 17        | BUSY     |
| GP4     | 6        | 15          | 22        | DC       |
| GP5     | 7        | 37          | 26        | CS0      |
| GP6     | 9        | 36          | 16        | CS1      |
| GP10    | 14       | 23          | 11        | SCLK     |
| GP11    | 15       | 19          | 10        | MOSI     |
| 3V3     | 36       | 1           | --        | 3.3V     |
| VBUS    | 40       | 2           | --        | 5V       |
| GND     | 3        | 6           | --        | GND      |
| GND     | 8        | 9           | --        | GND      |

Display pin numbers refer to the 40-pin Raspberry Pi-style header on the Inky Impression PCB. BCM
column shows the equivalent Broadcom GPIO number on a Pi Zero (for cross-referencing with the Python
driver and protocol docs).

### Test firmware

`bin/inky-test/` — three files, no lib dependencies:

- `main.zig` — GPIO/SPI/UART init, display init sequence, solid color fill, refresh
- `hal.zig` — clock (150 MHz), GPIO, SPI1 (5 MHz), UART0 (115200), timers, LED blink
- `boot.zig` — picobin block, vector table, reset handler, FPU enable, AEABI wrappers

Build and flash:

```bash
zig build inky-test -Doptimize=ReleaseFast
picotool load zig-out/inky-test.uf2 -f && picotool reboot
```

If picotool can't connect, hold BOOTSEL while plugging USB, then:

```bash
picotool load zig-out/inky-test.uf2 && picotool reboot
```

Serial monitor (via debug probe Pico):

```bash
screen /dev/tty.usbmodem* 115200
```

---

## Protocol Summary

The test firmware implements the exact protocol documented in `docs/inky-impression-13-protocol.md`,
which was reverse-engineered from the working Pi Zero Python driver.

### Init sequence

1. Hardware reset: RESET LOW 30ms, RESET HIGH 30ms
2. 17 SPI commands (no inter-command delays):
   - 9 commands to `.both` (CS0 and CS1 simultaneously)
   - 8 commands to `.cs0` only (power, booster, buffer config)
3. Data transfer: send DTM (0x10), then 480,000 bytes per controller half
4. Refresh: PON (0x04) → 300ms wait → DRF (0x12, 0x00) → wait 30-40s → POF (0x02, 0x00)

### SPI command protocol

```
1. selectChip(cs)        — pull target CS low, other CS high
2. DC LOW                — command mode
3. wait 1 us
4. SPI write command byte
5. if data bytes:
   a. DC HIGH            — data mode
   b. wait 1 us
   c. SPI write data bytes
6. wait 1 us
7. deselectChips()       — both CS high
8. DC LOW
```

### Chip select logic

| Target | GP5 (CS0) | GP6 (CS1) |
| ------ | --------- | --------- |
| CS0    | LOW       | HIGH      |
| CS1    | HIGH      | LOW       |
| both   | LOW       | LOW       |
| none   | HIGH      | HIGH      |

### Data streaming

```
1. sendCommand(0x10, cs, {})    — start data write
2. DC HIGH
3. selectChip(cs)
4. wait 1 us
5. SPI write 1600 rows x 300 bytes (480,000 bytes total)
6. wait 1 us
7. deselectChips()
8. DC LOW
```

The test fills CS0 with 0x33 (red) and CS1 with 0x55 (blue).

---

## Code Comparison: inky-test vs inky-zero (Pi Zero Python driver)

Verified that inky-test matches the known-good protocol exactly:

| Aspect             | inky-test (Pico 2)      | inky-zero (Pi Zero)     | Match? |
| ------------------ | ----------------------- | ----------------------- | ------ |
| Init commands      | 17 commands, same order | 17 commands, same order | Yes    |
| Command data bytes | Identical               | Identical               | Yes    |
| CS targets per cmd | Identical               | Identical               | Yes    |
| SPI mode           | Mode 0                  | Mode 0                  | Yes    |
| SPI speed          | 5 MHz                   | 10 MHz                  | OK     |
| Reset timing       | 30ms low, 30ms high     | 30ms low, 30ms high     | Yes    |
| Post-PON delay     | 300ms                   | 300ms                   | Yes    |
| DC protocol        | Same toggle sequence    | Same toggle sequence    | Yes    |
| Pixel packing      | 2px/byte, 4-bit nibbles | Same                    | Yes    |
| Data size per half | 480,000 bytes           | Same                    | Yes    |

The only difference is SPI clock speed (5 MHz vs 10 MHz), which is well within spec.

---

## Tests Performed

### Test 1: Normal wiring — CS0 red, CS1 blue

**Wiring:** GP5→pin 37 (CS0), GP6→pin 36 (CS1) **Result:** Bottom half (CS0) renders red. Top half
(CS1) unchanged. **Conclusion:** CS0 works, CS1 does not respond.

### Test 2: Swap wires — GP5→pin 36 (CS1), GP6→pin 37 (CS0)

**Wiring:** GP5→pin 36 (CS1), GP6→pin 37 (CS0) **Code:** Pin assignments NOT changed — so CS0
init/power commands go to display CS1, CS1 data goes to display CS0. **Result:** Nothing renders on
either half. **Conclusion:** Expected — CS0 controller didn't get its power/booster init commands
(those went to the unresponsive CS1 controller via the swapped wire).

### Test 3: Swap wires + swap pin assignments in code

**Wiring:** GP5→pin 36 (CS1), GP6→pin 37 (CS0) **Code:** `pin_cs0 = 6`, `pin_cs1 = 5` (matching the
swapped wiring) **Result:** Bottom half (CS0, now driven by GP6) renders red. Top half (CS1, now
driven by GP5) still unchanged. **Conclusion:**

- **GP6 can successfully drive CS0** — proves GP6 outputs a valid signal
- **GP5 cannot drive CS1** — but GP5 drove CS0 fine in test 1
- **Both GPIOs work.** The problem is display pin 36 (CS1 line on the display PCB).

---

## Conclusion

The CS1 controller on this display unit does not respond to any commands regardless of which GPIO
drives display pin 36. Both Pico GPIOs (GP5 and GP6) are confirmed working — each can successfully
drive the CS0 controller.

**Root cause:** Hardware fault on the display — either the CS1 trace, the CS1 controller chip, or
the connection between display pin 36 and the EL133UF1 CS1 input.

**Possible history:** The display may have been damaged during a prior session where a ribbon cable
was connected in reverse orientation (components got hot).

---

## Next Step

**Verify with Pi Zero:** Connect the display to the Pi Zero 2 W and run the Python driver. If CS1
works on the Pi Zero, the issue is electrical (voltage levels, edge timing, drive strength) rather
than a dead controller. If CS1 also fails on the Pi Zero, the display hardware is confirmed damaged.

### Pi Zero test procedure

1. Disconnect all jumper wires from Pico
2. Connect display to Pi Zero via ribbon cable or HAT header
3. Run the Python driver with a full-screen test pattern
4. Observe whether both halves update

If CS1 works on the Pi Zero, investigate:

- Pico GPIO drive strength (default 4mA vs Pi's 8mA)
- Pad slew rate configuration
- Signal integrity on the jumper wire (try shorter wire for CS1)
