# Inky Impression 13 (Spectra 6) Display Protocol

This document describes the low-level communication protocol for the Inky Impression 13 e-ink
display (Spectra 6, 1600x1200, 6-color). The information was extracted from the Pimoroni Python
driver to enable a standalone C implementation.

## Display Specifications

| Property           | Value              |
| ------------------ | ------------------ |
| Resolution         | 1600 x 1200 pixels |
| Colors             | 6 (Spectra 6)      |
| Controller         | EL133UF1           |
| Interface          | SPI + GPIO + I2C   |
| Display Variant ID | 21                 |
| EEPROM Address     | 0x50 (I2C)         |

---

## EEPROM Auto-Detection

The display includes an I2C EEPROM at address `0x50` that stores display metadata. This allows
automatic detection of display type and resolution.

### EEPROM Data Structure (29 bytes)

| Offset | Size | Field           | Format        |
| ------ | ---- | --------------- | ------------- |
| 0      | 2    | Width           | uint16_le     |
| 2      | 2    | Height          | uint16_le     |
| 4      | 1    | Color type      | uint8         |
| 5      | 1    | PCB variant     | uint8 (÷10)   |
| 6      | 1    | Display variant | uint8         |
| 7      | 22   | Write timestamp | Pascal string |

### Color Type Values

| Value | Color Type |
| ----- | ---------- |
| 1     | black      |
| 2     | red        |
| 3     | yellow     |
| 5     | 7colour    |
| 6     | spectra6   |
| 7     | red/yellow |

### Display Variant Table

| ID  | Display Model                            |
| --- | ---------------------------------------- |
| 1   | Red pHAT (High-Temp)                     |
| 2   | Yellow wHAT                              |
| 3   | Black wHAT                               |
| 4   | Black pHAT                               |
| 5   | Yellow pHAT                              |
| 6   | Red wHAT                                 |
| 7   | Red wHAT (High-Temp)                     |
| 8   | Red wHAT                                 |
| 10  | Black pHAT (SSD1608)                     |
| 11  | Red pHAT (SSD1608)                       |
| 12  | Yellow pHAT (SSD1608)                    |
| 14  | 7-Colour (UC8159)                        |
| 15  | 7-Colour 640x400 (UC8159)                |
| 16  | 7-Colour 640x400 (UC8159)                |
| 17  | Black wHAT (SSD1683)                     |
| 18  | Red wHAT (SSD1683)                       |
| 19  | Yellow wHAT (SSD1683)                    |
| 20  | 7-Colour 800x480 (AC073TC1A)             |
| 21  | **Spectra 6 13.3" 1600x1200 (EL133UF1)** |
| 22  | Spectra 6 7.3" 800x480 (E673)            |
| 23  | Red/Yellow pHAT (JD79661)                |
| 24  | Red/Yellow wHAT (JD79668)                |
| 25  | Spectra 6 4.0" 600x400 (E640)            |

### Reading EEPROM (C pseudocode)

```c
// I2C read from address 0x50
i2c_write(0x50, {0x00, 0x00});  // Set read pointer to 0
uint8_t eeprom[29];
i2c_read(0x50, eeprom, 29);

uint16_t width = eeprom[0] | (eeprom[1] << 8);
uint16_t height = eeprom[2] | (eeprom[3] << 8);
uint8_t color_type = eeprom[4];
float pcb_variant = eeprom[5] / 10.0;
uint8_t display_variant = eeprom[6];
// eeprom[7..28] = timestamp string
```

## Architecture Overview

**Critical: Dual-Controller Design**

The display is controlled by TWO separate e-ink drivers, each handling half of the display.
Communication uses two chip select lines (CS0 and CS1) to address each half independently or both
simultaneously.

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

After rotating the image -90 degrees (clockwise), the display is split at column 600:

- **CS0**: Columns 0-599 (left half in rotated orientation)
- **CS1**: Columns 600-1199 (right half in rotated orientation)

Each half contains 1600 rows × 600 columns = 960,000 pixels.

---

## Color Encoding

The display uses a 3-bit color encoding with values 0-6. **Note: Value 4 is skipped.**

| Index | Color    | Binary |
| ----- | -------- | ------ |
| 0     | Black    | 000    |
| 1     | White    | 001    |
| 2     | Yellow   | 010    |
| 3     | Red      | 011    |
| 4     | (unused) | 100    |
| 5     | Blue     | 101    |
| 6     | Green    | 110    |

**Note:** Pixel values should be masked with `& 0x07` to ensure only the lower 3 bits are used.

If using a sequential palette (0-5 for 6 colors), remap before sending:

```
palette_index:  0  1  2  3  4  5
display_value:  0  1  2  3  5  6
```

### RGB Color Palettes (for Preview/Dithering)

When displaying images or creating previews, use these RGB approximations of the e-ink colors. Blend
between the two palettes based on desired realism level.

**Pure RGB Palette** (ideal colors for dithering input):

| Index | Color  | R   | G   | B   | Hex       |
| ----- | ------ | --- | --- | --- | --------- |
| 0     | Black  | 0   | 0   | 0   | `#000000` |
| 1     | White  | 255 | 255 | 255 | `#FFFFFF` |
| 2     | Yellow | 255 | 255 | 0   | `#FFFF00` |
| 3     | Red    | 255 | 0   | 0   | `#FF0000` |
| 4     | Blue   | 0   | 0   | 255 | `#0000FF` |
| 5     | Green  | 0   | 255 | 0   | `#00FF00` |

**Measured E-ink Palette** (realistic display appearance):

| Index | Color  | R   | G   | B   | Hex       |
| ----- | ------ | --- | --- | --- | --------- |
| 0     | Black  | 0   | 0   | 0   | `#000000` |
| 1     | White  | 161 | 164 | 165 | `#A1A4A5` |
| 2     | Yellow | 208 | 190 | 71  | `#D0BE47` |
| 3     | Red    | 156 | 72  | 75  | `#9C484B` |
| 4     | Blue   | 61  | 59  | 94  | `#3D3B5E` |
| 5     | Green  | 58  | 91  | 70  | `#3A5B46` |

**Palette blending formula:**

```c
// realism: 0.0 = pure RGB, 1.0 = measured e-ink appearance
for (int i = 0; i < 6; i++) {
    r[i] = measured[i].r * realism + pure[i].r * (1.0 - realism);
    g[i] = measured[i].g * realism + pure[i].g * (1.0 - realism);
    b[i] = measured[i].b * realism + pure[i].b * (1.0 - realism);
}
```

---

## Pixel Packing Format

Two pixels are packed into each byte using 4-bit nibbles:

```
Byte layout:  [PPPP QQQQ]
               ^^^^----- First pixel (even index) in high nibble
                    ^^^^- Second pixel (odd index) in low nibble

Example:
  Pixels: [Black, White, Yellow, Red, Blue, Green]
  Values: [0, 1, 2, 3, 5, 6]

  Byte 0: (0 << 4) | 1 = 0x01
  Byte 1: (2 << 4) | 3 = 0x23
  Byte 2: (5 << 4) | 6 = 0x56
```

**Packing algorithm:**

```c
// For an array of pixels where pixels[i] is a value 0-6
for (int i = 0; i < num_pixels; i += 2) {
    packed[i/2] = ((pixels[i] << 4) & 0xF0) | (pixels[i+1] & 0x0F);
}
```

**Buffer sizes:**

- Each half: 960,000 pixels / 2 = 480,000 bytes
- Total image data: 960,000 bytes

---

## Hardware Interface

### GPIO Pin Assignments

| Function | BCM Pin | Physical Pin | Direction       |
| -------- | ------- | ------------ | --------------- |
| RESET    | 27      | 13           | Output          |
| BUSY     | 17      | 11           | Input (pull-up) |
| DC       | 22      | 15           | Output          |
| CS0      | 26      | 37           | Output          |
| CS1      | 16      | 36           | Output          |
| MOSI     | 10      | 19           | Output (SPI)    |
| SCLK     | 11      | 23           | Output (SPI)    |

### SPI Configuration

| Parameter   | Value                  |
| ----------- | ---------------------- |
| SPI Bus     | 0                      |
| SPI Channel | 0 (but CS is manual)   |
| Clock Speed | 10 MHz (10,000,000 Hz) |
| Mode        | 0 (CPOL=0, CPHA=0)     |
| Bit Order   | MSB first              |

**Important:** Chip select is managed manually via GPIO, not by the SPI hardware. Use `spidev`'s
`xfer3()` method (non-blocking transfer) rather than `xfer()` for better performance with large
buffers.

### Chip Select Logic

```
CS0_SEL = 0b01  // Select first controller
CS1_SEL = 0b10  // Select second controller
CS_BOTH = 0b11  // Select both controllers

To select CS0:  Set GPIO 26 LOW, GPIO 16 HIGH
To select CS1:  Set GPIO 26 HIGH, GPIO 16 LOW
To select BOTH: Set GPIO 26 LOW, GPIO 16 LOW
To deselect:    Set GPIO 26 HIGH, GPIO 16 HIGH
```

---

## SPI Command Protocol

### Command Structure

The DC (Data/Command) pin distinguishes between command bytes and data bytes:

- **DC LOW**: Byte is a command
- **DC HIGH**: Byte is data

### Sending a Command

```
1. Set appropriate chip select(s) LOW (active)
2. Set DC pin LOW (command mode)
3. Wait ~300ms (critical timing!)
4. Send command byte via SPI
5. If data follows:
   a. Set DC pin HIGH (data mode)
   b. Send data bytes via SPI
6. Set both chip selects HIGH (inactive)
7. Set DC pin LOW
```

**Pseudocode:**

```c
void send_command(uint8_t cmd, uint8_t cs_sel, uint8_t *data, size_t len) {
    // Activate chip select(s)
    if (cs_sel & 0x01) gpio_set(CS0_PIN, LOW);
    if (cs_sel & 0x02) gpio_set(CS1_PIN, LOW);

    // Send command
    gpio_set(DC_PIN, LOW);
    delay_ms(300);  // Important delay!
    spi_write(&cmd, 1);

    // Send data if present
    if (data != NULL && len > 0) {
        gpio_set(DC_PIN, HIGH);
        spi_write(data, len);
    }

    // Deactivate
    gpio_set(CS0_PIN, HIGH);
    gpio_set(CS1_PIN, HIGH);
    gpio_set(DC_PIN, LOW);
}
```

---

## Display Commands (EL133UF1)

### Command Reference Table

| Name            | Code | Description                         |
| --------------- | ---- | ----------------------------------- |
| PSR             | 0x00 | Panel Setting Register              |
| PWR             | 0x01 | Power Setting                       |
| POF             | 0x02 | Power Off                           |
| PON             | 0x04 | Power On                            |
| BTST_N          | 0x05 | Booster Soft Start (Negative)       |
| BTST_P          | 0x06 | Booster Soft Start (Positive)       |
| DTM             | 0x10 | Data Transmission Mode (image data) |
| DRF             | 0x12 | Display Refresh                     |
| PLL             | 0x30 | PLL Control                         |
| TSC             | 0x40 | Temperature Sensor Command          |
| TSE             | 0x41 | Temperature Sensor Enable           |
| TSW             | 0x42 | Temperature Sensor Write            |
| TSR             | 0x43 | Temperature Sensor Read             |
| CDI             | 0x50 | VCOM and Data Interval Setting      |
| LPD             | 0x51 | Low Power Detection                 |
| TCON            | 0x60 | TCON Setting                        |
| TRES            | 0x61 | Resolution Setting                  |
| DAM             | 0x65 | Data Access Mode                    |
| REV             | 0x70 | Revision                            |
| FLG             | 0x71 | Flag Status                         |
| ANTM            | 0x74 | Anti-noise Timing                   |
| AMV             | 0x80 | Auto Measure VCOM                   |
| VV              | 0x81 | VCOM Value                          |
| VDCS            | 0x82 | VCOM DC Setting                     |
| PTLW            | 0x83 | Partial Window                      |
| AGID            | 0x86 | Auto Gate ID                        |
| BUCK_BOOST_VDDN | 0xB0 | Buck Boost VDDN                     |
| TFT_VCOM_POWER  | 0xB1 | TFT VCOM Power                      |
| EN_BUF          | 0xB6 | Enable Buffer                       |
| BOOST_VDDP_EN   | 0xB7 | Boost VDDP Enable                   |
| CCSET           | 0xE0 | Cascade Setting                     |
| PWS             | 0xE3 | Power Saving                        |
| TSSET           | 0xE5 | Temperature Sensor Setting          |
| CMD66           | 0xF0 | Undocumented Command                |

---

## Initialization Sequence

### 1. Hardware Reset

```c
gpio_set(RESET_PIN, LOW);
delay_ms(30);
gpio_set(RESET_PIN, HIGH);
delay_ms(30);
busy_wait(300);  // Wait up to 300ms for BUSY pin
```

### 2. Initialization Commands

Commands must be sent in this exact order:

```c
// Anti-noise timing (CS0 only)
send_command(0x74, CS0, {0xC0, 0x1C, 0x1C, 0xCC, 0xCC, 0xCC, 0x15, 0x15, 0x55}, 9);

// Undocumented init command (both)
send_command(0xF0, CS_BOTH, {0x49, 0x55, 0x13, 0x5D, 0x05, 0x10}, 6);

// Panel setting (both)
send_command(0x00, CS_BOTH, {0xDF, 0x69}, 2);

// PLL control (both)
send_command(0x30, CS_BOTH, {0x08}, 1);

// VCOM and data interval (both)
send_command(0x50, CS_BOTH, {0xF7}, 1);

// TCON setting (both)
send_command(0x60, CS_BOTH, {0x03, 0x03}, 2);

// Auto gate ID (both)
send_command(0x86, CS_BOTH, {0x10}, 1);

// Power saving (both)
send_command(0xE3, CS_BOTH, {0x22}, 1);

// Cascade setting (both)
send_command(0xE0, CS_BOTH, {0x01}, 1);

// Resolution setting (both)
// Bytes: [width_hi, width_lo, height_hi, height_lo]
// For 1200x800 per half (after rotation considerations)
send_command(0x61, CS_BOTH, {0x04, 0xB0, 0x03, 0x20}, 4);

// Power setting (CS0 only)
send_command(0x01, CS0, {0x0F, 0x00, 0x28, 0x2C, 0x28, 0x38}, 6);

// Enable buffer (CS0 only)
send_command(0xB6, CS0, {0x07}, 1);

// Booster soft start positive (CS0 only)
send_command(0x06, CS0, {0xD8, 0x18}, 2);

// Boost VDDP enable (CS0 only)
send_command(0xB7, CS0, {0x01}, 1);

// Booster soft start negative (CS0 only)
send_command(0x05, CS0, {0xD8, 0x18}, 2);

// Buck boost VDDN (CS0 only)
send_command(0xB0, CS0, {0x01}, 1);

// TFT VCOM power (CS0 only)
send_command(0xB1, CS0, {0x02}, 1);
```

---

## Display Update Sequence

### Complete Update Flow

```c
void update_display(uint8_t *buf_a, uint8_t *buf_b) {
    // buf_a: 480,000 bytes for CS0 half
    // buf_b: 480,000 bytes for CS1 half

    // 1. Run initialization
    init_display();

    // 2. Send image data
    send_command(0x10, CS0, buf_a, 480000);  // DTM to CS0
    send_command(0x10, CS1, buf_b, 480000);  // DTM to CS1

    // 3. Power on
    send_command(0x04, CS_BOTH, NULL, 0);    // PON
    busy_wait(200);                          // Wait up to 200ms

    // 4. Trigger refresh
    send_command(0x12, CS_BOTH, {0x00}, 1);  // DRF
    busy_wait(32000);                        // E-ink refresh: up to 32 SECONDS!

    // 5. Power off
    send_command(0x02, CS_BOTH, {0x00}, 1);  // POF
    busy_wait(200);                          // Wait up to 200ms
}
```

---

## BUSY Pin Handling

The BUSY pin indicates when the display is ready for commands:

- **BUSY HIGH (pulled up)**: Display is busy or not responding
- **BUSY LOW**: Display is ready

```c
void busy_wait(uint32_t timeout_ms) {
    // If BUSY is high (pulled up by host), display may not be connected
    // In that case, just wait the full timeout as a safety measure
    if (gpio_read(BUSY_PIN) == HIGH) {
        delay_ms(timeout_ms);
        return;
    }

    uint32_t start = get_time_ms();
    while (gpio_read(BUSY_PIN) == HIGH) {
        delay_ms(100);
        if (get_time_ms() - start > timeout_ms) {
            // Timeout - display may be stuck
            break;
        }
    }
}
```

**Expected wait times:**

- After reset: ~300ms
- After power on/off: ~200ms
- After display refresh: **up to 32 seconds** (e-ink is slow!)

---

## Image Data Preparation

### Optional Flip Operations

Before rotation, the image can be optionally flipped:

- **Horizontal flip (h_flip)**: Flip top-to-bottom (`flipud` in numpy)
- **Vertical flip (v_flip)**: Flip left-to-right (`fliplr` in numpy)

These operations are applied before the mandatory rotation step.

### Step-by-Step Process

1. **Start with 1600x1200 image** where each pixel is a color index (0, 1, 2, 3, 5, or 6)

2. **Apply optional flips** (if enabled):
   - v_flip: Mirror left-to-right
   - h_flip: Mirror top-to-bottom

3. **Rotate 90 degrees clockwise** (-90 degrees / 270 degrees CCW):
   - Result: 1200x1600 array (1200 columns, 1600 rows)
   - Coordinate transform: `new[col][height-1-row] = old[row][col]`

4. **Split into two halves:**
   - `buf_a`: Columns 0-599 → flatten row-by-row to 1D array of 960,000 pixels
   - `buf_b`: Columns 600-1199 → flatten row-by-row to 1D array of 960,000 pixels

5. **Pack pixels into bytes:**
   - For each pair of consecutive pixels [P0, P1]:
     - `byte = (P0 << 4) | P1`
   - Result: 480,000 bytes per buffer

### C Implementation Sketch

```c
void prepare_image(uint8_t *image_1600x1200,
                   uint8_t *buf_a,
                   uint8_t *buf_b) {
    // image_1600x1200: input, row-major, 1,920,000 bytes
    // buf_a, buf_b: output, 480,000 bytes each

    // After -90 rotation:
    // new[new_row][new_col] = old[old_row][old_col]
    // where new_row = old_col, new_col = (height-1) - old_row

    const int W = 1600, H = 1200;

    // Rotated dimensions: 1200 cols x 1600 rows
    int idx_a = 0, idx_b = 0;

    for (int new_row = 0; new_row < W; new_row++) {        // 1600 rows
        for (int new_col = 0; new_col < H; new_col++) {    // 1200 cols
            // Map back to original coordinates
            int old_row = (H - 1) - new_col;
            int old_col = new_row;
            uint8_t pixel = image_1600x1200[old_row * W + old_col];

            // Assign to correct buffer based on column
            if (new_col < 600) {
                // CS0 buffer (first 600 columns)
                if (idx_a % 2 == 0) {
                    buf_a[idx_a/2] = (pixel << 4);
                } else {
                    buf_a[idx_a/2] |= (pixel & 0x0F);
                }
                idx_a++;
            } else {
                // CS1 buffer (columns 600-1199)
                if (idx_b % 2 == 0) {
                    buf_b[idx_b/2] = (pixel << 4);
                } else {
                    buf_b[idx_b/2] |= (pixel & 0x0F);
                }
                idx_b++;
            }
        }
    }
}
```

---

## Minimal Raspberry Pi Setup

### Required Kernel Modules

- `spi-bcm2835` (SPI driver)
- `spidev` (userspace SPI access)

### Enable SPI

Add to `/boot/config.txt`:

```
dtparam=spi=on
```

### Accessing SPI from C

**Option 1: Linux spidev interface**

```c
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

int spi_fd = open("/dev/spidev0.0", O_RDWR);
uint32_t speed = 10000000;
uint8_t mode = SPI_MODE_0;
ioctl(spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);
ioctl(spi_fd, SPI_IOC_WR_MODE, &mode);
```

**Option 2: Direct register access (no kernel driver)**

- Map BCM2835 peripherals via `/dev/mem`
- More complex but zero dependencies

### Accessing GPIO from C

**Option 1: Linux GPIO character device (recommended)**

```c
#include <linux/gpio.h>
// Use /dev/gpiochip0 with ioctl
```

**Option 2: sysfs (deprecated but simple)**

```bash
echo 27 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio27/direction
echo 1 > /sys/class/gpio/gpio27/value
```

**Option 3: Direct register access**

- Map GPIO registers via `/dev/mem`

---

## Timing Summary

| Operation                | Duration             |
| ------------------------ | -------------------- |
| Reset pulse (low)        | 30 ms                |
| Reset recovery (high)    | 30 ms                |
| Post-reset busy wait     | 300 ms               |
| Command preamble delay   | 300 ms               |
| Post-power-on busy wait  | 200 ms               |
| Display refresh          | **up to 32 seconds** |
| Post-power-off busy wait | 200 ms               |

---

## Appendix: Command Byte Summary

```c
#define CMD_PSR          0x00  // Panel Setting
#define CMD_PWR          0x01  // Power Setting
#define CMD_POF          0x02  // Power Off
#define CMD_PON          0x04  // Power On
#define CMD_BTST_N       0x05  // Booster Soft Start (N)
#define CMD_BTST_P       0x06  // Booster Soft Start (P)
#define CMD_DTM          0x10  // Data Transmission Mode
#define CMD_DRF          0x12  // Display Refresh
#define CMD_PLL          0x30  // PLL Control
#define CMD_CDI          0x50  // VCOM/Data Interval
#define CMD_TCON         0x60  // TCON Setting
#define CMD_TRES         0x61  // Resolution Setting
#define CMD_ANTM         0x74  // Anti-noise Timing
#define CMD_AGID         0x86  // Auto Gate ID
#define CMD_BUCK_VDDN    0xB0  // Buck Boost VDDN
#define CMD_TFT_VCOM     0xB1  // TFT VCOM Power
#define CMD_EN_BUF       0xB6  // Enable Buffer
#define CMD_BOOST_VDDP   0xB7  // Boost VDDP Enable
#define CMD_CCSET        0xE0  // Cascade Setting
#define CMD_PWS          0xE3  // Power Saving
#define CMD_CMD66        0xF0  // Undocumented Init
```

---

## Open Questions / Areas for Investigation

1. **TRES (0x61) resolution values**: The bytes sent are `{0x04, 0xB0, 0x03, 0x20}` which decodes to
   1200×800 = 960,000 pixels. This matches the pixel count per controller half (1600×600 = 960,000
   after rotation and split), suggesting the controller may use a different internal arrangement.

2. **Timing margins**: The 300ms command preamble delay seems excessive. Testing may reveal if this
   can be reduced.

3. **Partial update support**: The PTLW (0x83) command suggests partial updates may be possible, but
   this isn't used in the Python driver.

4. **Border color**: The driver tracks a border color setting but doesn't appear to send it to the
   display. The CDI (0x50) register may control this, but it's always set to 0xF7.

---

## References

- Original source: Pimoroni Inky library (MIT License)
  - https://github.com/pimoroni/inky
- Display: Inky Impression 13.3" (Spectra 6)
- Controller: EL133UF1
