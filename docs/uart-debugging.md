# UART Debugging (Pico 2)

Serial debug output over UART, using a second Pico as a USB-to-serial bridge.

## What You Get

- **Progress messages**: prints at each stage of boot, init, render, refresh
- **Fault dumps**: on a HardFault/BusFault/UsageFault, prints all Cortex-M33 fault registers (CFSR,
  HFSR, MMFAR, BFAR) plus the stacked R0-R3, R12, LR, PC, and xPSR
- **Panic messages**: on a Zig panic (e.g. `unreachable`, index out of bounds), prints the panic
  message and return address

## Hardware Required

- A second Raspberry Pi Pico (Pico 1 or Pico 2)
- 2 jumper wires (female-female or male-female depending on your headers)
- 2 USB cables (one per Pico)

## Probe Setup (One-Time)

Flash the **debugprobe** firmware onto the second Pico:

1. Hold **BOOTSEL** on the probe Pico and plug it into your Mac/PC via USB
2. A USB mass storage drive appears (named "RPI-RP2" or "RP2350")
3. Download the firmware from
   [github.com/raspberrypi/debugprobe/releases](https://github.com/raspberrypi/debugprobe/releases):
   - Pico 1 probe: `debugprobe_on_pico.uf2`
   - Pico 2 probe: `debugprobe_on_pico2.uf2`
4. Drag the `.uf2` file onto the drive — the probe reboots automatically

The probe now acts as a USB-to-serial bridge. Its GP5 pin is the UART RX input.

## Wiring

Connect **2 wires** between the target Pico 2 and the probe Pico:

```
Target Pico 2                     Probe Pico
┌────────────────┐                ┌────────────────┐
│           GP0 ─┼────────────────┼─ GP5           │
│           GND ─┼────────────────┼─ GND           │
│           USB ─┼── power/flash  │           USB ─┼── to Mac/PC
└────────────────┘                └────────────────┘
```

| Target Pin | Probe Pin | Purpose       |
| ---------- | --------- | ------------- |
| GP0        | GP5       | UART TX → RX  |
| GND        | GND       | Common ground |

### Pico Header Pin Numbers

On both the Pico 1 and Pico 2 boards, counting from the USB connector end:

- **GP0** is physical pin 1 (top-left)
- **GND** is physical pin 3 (two pins down from GP0)
- **GP5** is physical pin 7 (four pins down from GP0)

GP0 is free — it is not used by the Inky display (which uses GP10, GP11, GP16, GP22, GP26, GP27).

## Connecting to the Serial Terminal

Both Picos must be plugged into your Mac/PC via USB. The probe shows up as a USB CDC serial device.

### macOS

```sh
# Find the device
ls /dev/tty.usbmodem*

# Connect (replace with your actual device path)
screen /dev/tty.usbmodem1102 115200
```

To exit `screen`: press `Ctrl-A`, then `K`, then `Y`.

### Linux

```sh
# Find the device
ls /dev/ttyACM*

# Connect
screen /dev/ttyACM0 115200
# or
minicom -D /dev/ttyACM0 -b 115200
```

To exit `minicom`: press `Ctrl-A`, then `X`.

### Settings

- Baud rate: **115200**
- Data bits: 8
- Parity: none
- Stop bits: 1
- Flow control: none

## Usage

1. Open the serial terminal (see above)
2. Flash a new `inky-pico.uf2` onto the target Pico 2 (BOOTSEL + drag)
3. Watch the output in the terminal

### Normal Boot Output

```
=== Ticking Away ===
display.init
render
Spectrum.init
refresh
done
```

### Fault Output

If the processor hits a HardFault, BusFault, MemManage, or UsageFault:

```
=== FAULT ===
CFSR: 0x00020000
HFSR: 0x40000000
MMFAR:0x00000000
BFAR: 0x00000000
R0:   0x3F800000
R1:   0x20001234
R2:   0x00000000
R3:   0x10003A4C
R12:  0x00000000
LR:   0x10003A20
PC:   0x10003A4C
xPSR: 0x61000000
```

### Panic Output

If the Zig runtime triggers a panic (e.g. `unreachable` reached, index out of bounds):

```
=== PANIC ===
index out of bounds
addr: 0x10002B8C
```

## Interpreting Fault Dumps

### CFSR (Configurable Fault Status Register)

The CFSR at `0xE000ED28` combines three sub-registers:

| Bits  | Sub-register | Common Flags (full CFSR values)                                                                |
| ----- | ------------ | ---------------------------------------------------------------------------------------------- |
| 7:0   | MMFSR        | `0x00000001` IACCVIOL, `0x00000002` DACCVIOL, `0x00000080` MMARVALID                           |
| 15:8  | BFSR         | `0x00000100` IBUSERR, `0x00000200` PRECISERR, `0x00000400` IMPRECISERR, `0x00008000` BFARVALID |
| 25:16 | UFSR         | `0x00010000` UNDEFINSTR, `0x00020000` INVSTATE, `0x01000000` UNALIGNED, `0x02000000` DIVBYZERO |

Common values:

- `0x00020000` — INVSTATE (invalid execution state, often a bad function pointer)
- `0x00010000` — UNDEFINSTR (undefined instruction, e.g. FPU instruction with FPU disabled)
- `0x00000400` — IMPRECISERR (imprecise bus fault, stale write buffer error)
- `0x00000200` — PRECISERR + check BFAR for the faulting address
- `0x01000000` — UNALIGNED (unaligned memory access)

### PC (Program Counter)

The stacked PC is the address of the faulting instruction. To find the corresponding source line:

```sh
# Disassemble around the faulting PC
zig objdump -d zig-out/bin/inky-pico | grep -A5 "10003a4c:"

# Or dump the full disassembly to a file for searching
zig objdump -d -S zig-out/bin/inky-pico > disasm.txt
```

### HFSR (HardFault Status Register)

- `0x40000000` — FORCED: the fault escalated from a configurable fault (check CFSR for the cause)
- `0x00000002` — VECTTBL: fault on vector table read during exception processing

## Adding Custom Debug Prints

UART is initialized early in `main()` via `hal.initUart()`, so prints work anywhere after that
point. The panic handler checks whether UART0 is out of reset before printing, so panics are
captured even if they occur during init.

```zig
hal.uartPrint("checkpoint reached\n");
hal.uartPrintHex(some_u32_value);
hal.uartPrint("\n");
```

For float values, print the raw IEEE 754 bits:

```zig
hal.uartPrintHex(@bitCast(some_f32_value));
```

Call `hal.uartFlush()` before any point where execution might not continue (e.g. before a suspicious
function call) to ensure all buffered output is transmitted.
