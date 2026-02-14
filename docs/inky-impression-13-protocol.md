# Inky Impression 13.3" (Spectra 6) Display Protocol

This document describes the low-level communication protocol for the Inky Impression 13.3" e-ink
display (Spectra 6, 1200x1600, 6-color). Originally reverse-engineered from the Pimoroni Python
driver, then verified and corrected through hardware testing.

## Display Specifications

| Property   | Value              |
| ---------- | ------------------ |
| Resolution | 1200 x 1600 pixels |
| Colors     | 6 (Spectra 6)      |
| Controller | EL133UF1 (x2)      |
| Interface  | SPI + GPIO         |

---

## Architecture

### Dual-Controller Design

The display uses two independent e-ink controllers, each driving half the display. They share a
single SPI bus and are addressed via separate chip select lines (active low).

```
+------------------+------------------+
|                  |                  |
|     CS0 Half     |     CS1 Half     |
|   (600 columns)  |   (600 columns)  |
|                  |                  |
+------------------+------------------+
        ^                   ^
        |                   |
   Chip Select 0       Chip Select 1
        |                   |
        +-------+   +-------+
                |   |
              SPI Bus
```

The image is rendered at 1200x1600 (landscape) and rotated 90 degrees clockwise for the display's
native portrait orientation. After rotation, the 1200 columns split at column 600:

- **CS0**: Columns 0-599 (left half)
- **CS1**: Columns 600-1199 (right half)

Each half: 1600 rows x 600 columns = 960,000 pixels = 480,000 packed bytes.

---

## Hardware Interface

### GPIO Pin Assignments

| Function | BCM Pin | Direction |
| -------- | ------- | --------- |
| RESET    | 27      | Output    |
| DC       | 22      | Output    |
| CS0      | 26      | Output    |
| CS1      | 16      | Output    |
| MOSI     | 10      | SPI       |
| SCLK     | 11      | SPI       |
| BUSY     | 17      | (unused)  |

**BUSY pin note:** The BUSY pin (BCM 17) is active-low and wired with a pull-up resistor. On this
hardware it always reads HIGH, making it unusable for command completion detection. All timing uses
fixed delays instead.

### SPI Configuration

| Parameter   | Value                  |
| ----------- | ---------------------- |
| SPI Device  | `/dev/spidev0.0`       |
| Clock Speed | 10 MHz (10,000,000 Hz) |
| Mode        | 0 (CPOL=0, CPHA=0)     |

Chip select is managed manually via GPIO, not by the SPI hardware.

### Chip Select Logic

All active low:

```
To select CS0:  GPIO 26 LOW,  GPIO 16 HIGH
To select CS1:  GPIO 26 HIGH, GPIO 16 LOW
To select both: GPIO 26 LOW,  GPIO 16 LOW
To deselect:    GPIO 26 HIGH, GPIO 16 HIGH
```

---

## Color Encoding

The display uses 3-bit color values 0-6. **Value 4 is skipped.**

| Value | Color  |
| ----- | ------ |
| 0     | Black  |
| 1     | White  |
| 2     | Yellow |
| 3     | Red    |
| 5     | Blue   |
| 6     | Green  |

If using a sequential palette (indices 0-5), remap before sending:

```
palette_index:  0  1  2  3  4  5
display_value:  0  1  2  3  5  6
```

---

## Pixel Packing

Two pixels per byte, 4-bit nibbles:

```
Byte: [PPPP QQQQ]
       ^^^^        first pixel (even) in high nibble
            ^^^^   second pixel (odd) in low nibble

Example: Black, White, Yellow, Red, Blue, Green
Values:  0, 1, 2, 3, 5, 6
Bytes:   0x01, 0x23, 0x56
```

Each controller half receives 480,000 packed bytes (960,000 pixels / 2).

---

## SPI Command Protocol

The DC (Data/Command) pin distinguishes between command bytes and data bytes:

- **DC LOW**: byte is a command
- **DC HIGH**: byte is data

### Sending a Command

```
1. Select chip(s) (CS LOW)
2. Set DC LOW (command mode)
3. Send command byte via SPI
4. If data follows:
   a. Set DC HIGH (data mode)
   b. Send data bytes via SPI
5. Deselect all chips (CS HIGH)
6. Set DC LOW
```

No delay is needed within the command sequence itself. The only delays in the protocol are the
hardware reset (30ms low, 30ms recovery) and 300ms after the PON (power on) command before issuing
DRF (display refresh) — see the refresh sequence below.

---

## Command Reference

Commands used by this driver:

| Name       | Code | Target | Description                   |
| ---------- | ---- | ------ | ----------------------------- |
| PSR        | 0x00 | both   | Panel Setting Register        |
| PWR        | 0x01 | cs0    | Power Setting                 |
| POF        | 0x02 | both   | Power Off                     |
| PON        | 0x04 | both   | Power On                      |
| BTST_N     | 0x05 | cs0    | Booster Soft Start (Negative) |
| BTST_P     | 0x06 | cs0    | Booster Soft Start (Positive) |
| DTM        | 0x10 | each   | Data Transmission Mode        |
| DRF        | 0x12 | both   | Display Refresh               |
| PLL        | 0x30 | both   | PLL Control                   |
| CDI        | 0x50 | both   | VCOM and Data Interval        |
| TCON       | 0x60 | both   | TCON Setting                  |
| TRES       | 0x61 | both   | Resolution Setting            |
| ANTM       | 0x74 | cs0    | Anti-noise Timing             |
| AGID       | 0x86 | both   | Auto Gate ID                  |
| BUCK_VDDN  | 0xB0 | cs0    | Buck Boost VDDN               |
| TFT_VCOM   | 0xB1 | cs0    | TFT VCOM Power                |
| EN_BUF     | 0xB6 | cs0    | Enable Buffer                 |
| BOOST_VDDP | 0xB7 | cs0    | Boost VDDP Enable             |
| CCSET      | 0xE0 | both   | Cascade Setting               |
| PWS        | 0xE3 | both   | Power Saving                  |
| CMD_F0     | 0xF0 | both   | Undocumented Init             |

---

## Initialization Sequence

### 1. Hardware Reset

```
RESET LOW  → wait 30ms → RESET HIGH → wait 30ms
```

### 2. Register Configuration

All 17 commands are sent without delays. Order matters.

```
0x74  CS0   {0xC0, 0x1C, 0x1C, 0xCC, 0xCC, 0xCC, 0x15, 0x15, 0x55}      // Anti-noise timing
0xF0  both  {0x49, 0x55, 0x13, 0x5D, 0x05, 0x10}                        // Undocumented init
0x00  both  {0xDF, 0x69}                                                // Panel setting
0x30  both  {0x08}                                                      // PLL control
0x50  both  {0xF7}                                                      // VCOM and data interval
0x60  both  {0x03, 0x03}                                                // TCON setting
0x86  both  {0x10}                                                      // Auto gate ID
0xE3  both  {0x22}                                                      // Power saving
0xE0  both  {0x01}                                                      // Cascade setting
0x61  both  {0x04, 0xB0, 0x03, 0x20}                                    // Resolution (1200x800)
0x01  CS0   {0x0F, 0x00, 0x28, 0x2C, 0x28, 0x38}                        // Power setting
0xB6  CS0   {0x07}                                                      // Enable buffer
0x06  CS0   {0xD8, 0x18}                                                // Booster soft start (+)
0xB7  CS0   {0x01}                                                      // Boost VDDP enable
0x05  CS0   {0xD8, 0x18}                                                // Booster soft start (-)
0xB0  CS0   {0x01}                                                      // Buck boost VDDN
0xB1  CS0   {0x02}                                                      // TFT VCOM power
```

Initialization only needs to run once after reset, not before every update.

---

## Display Update Sequence

A complete update has three phases: data transfer, then refresh.

### 1. Data Transfer (per controller half)

For each half (CS0, then CS1):

```
1. Send DTM (0x10) command to select the controller
2. Set DC HIGH, select chip (enter data streaming mode)
3. Write packed pixel data via SPI (480,000 bytes)
4. Deselect chip, set DC LOW
```

Data can be streamed in chunks of any size. No delays are needed during transfer.

### 2. Refresh

```
1. Send PON (0x04) to both controllers
2. Wait 300ms (boost converter settling time)
3. Send DRF (0x12, data: 0x00) to both controllers
4. Send POF (0x02, data: 0x00) to both controllers
```

The physical e-paper update takes approximately 30-40 seconds after DRF. POF does not interrupt an
in-progress refresh — it queues a power-down for after the update completes.

### Timing Details

The 300ms delay after PON is the only required delay in the update sequence (apart from the hardware
reset delays). Testing showed:

- **200ms**: Too short — display does not update
- **300ms**: Works reliably
- **500ms**: Works (unnecessary margin)

No delays are needed for init commands, DTM, DRF, or POF.

---

## Timing Summary

| Operation              | Duration  | Notes                         |
| ---------------------- | --------- | ----------------------------- |
| Reset pulse (low)      | 30ms      |                               |
| Reset recovery (high)  | 30ms      |                               |
| Post-PON delay         | **300ms** | Boost converter settling time |
| Physical refresh (DRF) | ~30-40s   | E-ink update, non-blocking    |

---

## TRES Resolution Values

The TRES (0x61) command sends `{0x04, 0xB0, 0x03, 0x20}` which decodes as 1200 x 800 = 960,000
pixels. This matches the pixel count per controller half (1600 rows x 600 columns = 960,000 after
rotation and split), suggesting the controllers use a different internal row/column arrangement than
the physical display layout.

---

## EEPROM (Reference)

The display includes an I2C EEPROM at address `0x50` for auto-detection. Not used by this driver (we
hardcode the display configuration), but documented here for reference.

| Offset | Size | Field           | Format               |
| ------ | ---- | --------------- | -------------------- |
| 0      | 2    | Width           | uint16_le            |
| 2      | 2    | Height          | uint16_le            |
| 4      | 1    | Color type      | uint8 (6 = spectra6) |
| 5      | 1    | PCB variant     | uint8 (÷10)          |
| 6      | 1    | Display variant | uint8 (21)           |
| 7      | 22   | Write timestamp | Pascal string        |

---

## Open Questions

1. **Partial update support**: The PTLW (0x83) command suggests partial updates may be possible, but
   untested.

2. **Border color**: The CDI (0x50) register is set to 0xF7. It may control border behavior but
   hasn't been investigated.

---

## References

- Original Python driver: Pimoroni Inky library (MIT License)
  - https://github.com/pimoroni/inky
- Display: Inky Impression 13.3" (Spectra 6)
- Controller: EL133UF1
