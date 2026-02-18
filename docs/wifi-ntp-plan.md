# WiFi NTP Time Sync — Implementation Plan

Replace the build-time hardcoded timestamp with real-time NTP synchronization using the Pico 2 W's
built-in CYW43439 WiFi chip. This eliminates the need to flash promptly — the watchface will always
show the correct time.

## Problem

The current design captures `std.time.timestamp() + 90s` at build time and bakes it into the binary.
If flashing takes longer or shorter than the 90-second buffer, the clock starts wrong. Time can only
be corrected by re-building and re-flashing.

## Solution

On first boot (and optionally on subsequent wake cycles), connect to WiFi, send a single NTP
request, set the POWMAN timer to the received UTC time, then disconnect WiFi and proceed with the
normal render/sleep cycle. WiFi only needs to be active for a few seconds.

## Hardware Change

Replace the **Raspberry Pi Pico 2** with the **Raspberry Pi Pico 2 W**. Same form factor, same
pinout for user GPIOs. The only difference is the onboard CYW43439 WiFi/BT chip connected via
internal GPIOs (23, 24, 25, 29).

**Important:** GPIO 25 (onboard LED on Pico 2) becomes CYW43 chip-select on the Pico 2 W. GPIO 29
becomes the CYW43 SPI clock (it was ADC3/VSYS on Pico 2). Neither of these is used by the current
display driver, so there is no conflict.

## Architecture

```
Boot → Init Clocks → Init CYW43 (PIO SPI) → Connect WiFi → NTP Request → Set POWMAN Timer
  → Disconnect WiFi → Init Display SPI → Render → Sleep → Wake → (optional: re-sync) → Repeat
```

The CYW43 driver and lwIP stack are C libraries compiled by Zig's build system and called from Zig
via `@cImport` / `extern` declarations. The platform glue (HAL callbacks, PIO SPI transport) is
implemented in Zig, mapping to existing HAL functions where possible.

---

## Components

### 1. CYW43 Driver (C, from georgerobotics/cyw43-driver)

The CYW43439 is a full SoC with its own ARM core. It requires firmware uploaded over SPI at every
power-on. The driver handles firmware loading, bus protocol, WiFi association, and packet dispatch.

**Source files needed:**

| File            | Purpose                                              |
| --------------- | ---------------------------------------------------- |
| `cyw43_ctrl.c`  | High-level: init, WiFi join/scan, ethernet send      |
| `cyw43_ll.c`    | Low-level: bus init, firmware load, IOCTL, backplane |
| `cyw43_lwip.c`  | lwIP integration: netif, DHCP, link state callbacks  |
| `cyw43_spi.c`   | Generic gSPI protocol: command framing, register I/O |
| `cyw43_stats.c` | Optional statistics counters                         |

**Firmware files needed (embedded in flash as const arrays):**

| File                             | Size (source) | Binary size | Purpose             |
| -------------------------------- | ------------- | ----------- | ------------------- |
| `w43439A0_7_95_49_00_combined.h` | ~1.4 MB       | ~224 KB     | WiFi firmware + CLM |
| `wifi_nvram_43439.h`             | ~2 KB         | ~0.5 KB     | NVRAM calibration   |

The firmware source files are C header files containing `static const unsigned char[]` arrays. The
~1.4 MB source size compresses to ~224 KB of actual binary data embedded in flash.

**Configuration defines:**

```c
#define CYW43_USE_SPI        1
#define CYW43_LWIP           1
#define CYW43_GPIO           1
#define CYW43_SPI_PIO        1
#define CYW43_CHIPSET_FIRMWARE_INCLUDE_FILE "w43439A0_7_95_49_00_combined.h"
#define CYW43_WIFI_NVRAM_INCLUDE_FILE       "wifi_nvram_43439.h"
```

### 2. PIO SPI Transport (Zig, new)

The CYW43439 uses a non-standard half-duplex SPI protocol with a single bidirectional data line
(GPIO 24 serves as MOSI, MISO, and IRQ). Standard SPI hardware cannot drive this — RP2350's PIO
(Programmable I/O) is required.

**CYW43 SPI pin assignments (fixed on Pico 2 W PCB):**

| Signal           | GPIO | Notes                                               |
| ---------------- | ---- | --------------------------------------------------- |
| WL_ON (power)    | 23   | Drive high to enable CYW43, low to disable          |
| DATA (MOSI/MISO) | 24   | Half-duplex bidirectional, 470Ω protection resistor |
| CS (chip select) | 25   | Active low, directly driven                         |
| CLK (SPI clock)  | 29   | Directly driven                                     |
| IRQ (host wake)  | 24   | Shared with DATA, active between transactions       |

**No conflict with display SPI:** The display uses SPI1 hardware peripheral on GP10 (SCK) and GP11
(TX), with GPIO-controlled CS on GP16/GP26. The CYW43 uses PIO on completely separate pins (23-25,
29).

**PIO program:**

The Pico SDK's `cyw43_bus_pio_spi.pio` contains two PIO programs for the half-duplex protocol. We
have two options:

- **Option A:** Port the PIO assembly to Zig's PIO assembler (RP2350 PIO is well-documented).
- **Option B (recommended):** Extract the pre-assembled PIO instruction arrays from the Pico SDK's
  generated `cyw43_bus_pio_spi.pio.h` and embed them as Zig constants. PIO programs are just arrays
  of u16 instructions — no C dependency needed.

The PIO program clocks data out on rising edge, reads on falling edge, and switches pin direction
between TX and RX phases. DMA is used for bulk transfers with byte-swap enabled.

**Platform functions to implement (called by cyw43_spi.c):**

```c
int  cyw43_spi_init(cyw43_int_t *self);
void cyw43_spi_deinit(cyw43_int_t *self);
void cyw43_spi_gpio_setup(void);
void cyw43_spi_reset(void);
void cyw43_spi_set_polarity(cyw43_int_t *self, int pol);
int  cyw43_spi_transfer(cyw43_int_t *self, const uint8_t *tx, size_t tx_length,
                        uint8_t *rx, size_t rx_length);
```

**Note:** `cyw43_spi_set_polarity` is only called once during bus init (from `write_reg_u32_swap` in
`cyw43_spi.c`), always with argument `0` (CPOL=0). Since the PIO SPI program runs in a fixed Mode 0,
a no-op implementation is correct. Alternatively, provide a custom `write_reg_u32_swap` (as the Pico
SDK does) to avoid the call entirely.

### 3. CYW43 HAL Glue (Zig, new)

The driver calls platform HAL functions that we implement in Zig, mapping to our existing HAL:

| C function                                  | Zig implementation                                 |
| ------------------------------------------- | -------------------------------------------------- |
| `cyw43_hal_ticks_us()`                      | Read Timer0 TIMERAWL register (already in hal.zig) |
| `cyw43_hal_ticks_ms()`                      | `ticks_us / 1000`                                  |
| `cyw43_delay_us(us)`                        | `hal.sleepUs(us)`                                  |
| `cyw43_delay_ms(ms)`                        | `hal.sleepMs(ms)`                                  |
| `cyw43_hal_pin_config(pin, ...)`            | `hal.initGpioOutput(pin, ...)`                     |
| `cyw43_hal_pin_read(pin)`                   | Read SIO GPIO_IN register                          |
| `cyw43_hal_pin_low(pin)`                    | `hal.gpioSetLow(pin)`                              |
| `cyw43_hal_pin_high(pin)`                   | `hal.gpioSetHigh(pin)`                             |
| `cyw43_hal_get_mac(idx, buf)`               | Read MAC from RP2350 OTP memory                    |
| `cyw43_hal_generate_laa_mac(idx, buf)`      | Derive from OTP MAC                                |
| `cyw43_schedule_internal_poll_dispatch(fn)` | Direct call (single-threaded, no scheduler needed) |
| `cyw43_thread_enter()`                      | No-op (bare-metal, single-threaded)                |
| `cyw43_thread_exit()`                       | No-op                                              |

### 4. lwIP — Lightweight IP Stack (C, from lwip-tcpip/lwip)

Minimal UDP-only configuration for NTP. No TCP, no HTTP, no sockets API.

**Source files needed:**

Core:

- `core/init.c`, `core/def.c`, `core/mem.c`, `core/memp.c`, `core/pbuf.c`
- `core/netif.c`, `core/ip.c`, `core/udp.c`, `core/dns.c`
- `core/sys.c`, `core/timeouts.c`, `core/inet_chksum.c`

IPv4:

- `core/ipv4/ip4.c`, `core/ipv4/ip4_addr.c`, `core/ipv4/etharp.c`
- `core/ipv4/dhcp.c`, `core/ipv4/icmp.c`

Network interface:

- `netif/ethernet.c`

**Key lwipopts.h settings (minimize RAM):**

```c
#define NO_SYS                  1    // Bare-metal, no OS
#define MEM_SIZE                4000 // Heap size in bytes
#define MEMP_NUM_PBUF           4
#define MEMP_NUM_UDP_PCB        2
#define MEMP_NUM_TCP_PCB        0    // No TCP
#define PBUF_POOL_SIZE          4
#define PBUF_POOL_BUFSIZE       1536
#define LWIP_TCP                0    // Disable TCP
#define LWIP_UDP                1
#define LWIP_DHCP               1
#define LWIP_DNS                1
#define LWIP_ICMP               1
#define LWIP_ARP                1
#define LWIP_NETIF_HOSTNAME     1
#define SYS_LIGHTWEIGHT_PROT    1    // Protect critical sections (interrupt disable/enable)
#define LWIP_RAND()             /* use hw RNG or simple PRNG */
```

Estimated RAM: ~12-16 KB for lwIP with this configuration.

**sys_arch stubs (NO_SYS=1):** When `NO_SYS=1`, lwIP uses the "raw" callback API and does not
require any OS primitives (no mutexes, semaphores, or threads). Two things need real
implementations:

- `sys_now()` — return current time in milliseconds (read Timer0 TIMERAWL, convert to ms).
- `SYS_ARCH_PROTECT` / `SYS_ARCH_UNPROTECT` — lwIP calls these in `mem_malloc`, `pbuf_alloc`, etc.
  Set `SYS_LIGHTWEIGHT_PROT=1` in `lwipopts.h` and implement as interrupt disable/enable (`cpsid i`
  / `cpsie i` on Cortex-M33). Single-threaded bare-metal, so no mutex needed.

The caller must also call `sys_check_timeouts()` periodically (from the main polling loop) to drive
lwIP's internal timers (ARP, DHCP lease renewal, DNS retries).

### 5. NTP Client (Zig, new, ~50 lines)

Simple SNTP client using lwIP's raw UDP API. This is the easy part.

**Protocol:**

1. Resolve `pool.ntp.org` via `dns_gethostbyname()` (or hardcode a known NTP IP to skip DNS)
2. Allocate a 48-byte UDP packet (pbuf)
3. Set byte 0 to `0x1B` (LI=0, Version=3, Mode=3/client), zero the rest
4. Send to destination port 123 via `udp_sendto()`
5. Poll in a loop (`cyw43_ll_process_packets()` + `sys_check_timeouts()`) until the receive callback
   fires
6. In the receive callback, extract the transmit timestamp from offset 40-43 (big-endian u32)
7. Subtract `2_208_988_800` to convert NTP epoch (1900) to Unix epoch (1970)
8. Multiply by 1000 to get milliseconds, call `hal.setTimeMs()`
9. Clean up: `udp_remove()`, disconnect WiFi, deinit CYW43

**NTP packet layout (48 bytes):**

| Offset | Size | Field                                              |
| ------ | ---- | -------------------------------------------------- |
| 0      | 1    | LI (2b) + Version (3b) + Mode (3b) → send `0x1B`   |
| 1-39   | 39   | Stratum, poll, precision, timestamps → send as `0` |
| 40     | 4    | **Transmit timestamp seconds** (big-endian u32)    |
| 44     | 4    | Transmit timestamp fraction (unused)               |

### 6. WiFi Credentials

SSID and password must be stored somewhere. Options:

- **Option A (recommended):** Build-time options via `build.zig`, passed as `build_options`. Compile
  with `zig build inky-pico -Dssid="MyNetwork" -Dpassword="secret"`. Not stored in version control.
- **Option B:** Hardcoded in a `.zig` file excluded from git via `.gitignore`.
- **Option C:** Stored in RP2350 OTP (one-time programmable) memory. Permanent, cannot be changed.

---

## Memory Budget

**Flash (4 MB available):**

| Component                    | Estimated size |
| ---------------------------- | -------------- |
| Current binary (code + data) | ~450 KB        |
| CYW43 firmware blob          | ~224 KB        |
| CYW43 driver code            | ~30 KB         |
| lwIP code                    | ~40 KB         |
| PIO SPI + NTP + glue         | ~10 KB         |
| **Total**                    | **~754 KB**    |

Comfortable fit within 4 MB flash. ~3.2 MB headroom.

**SRAM (520 KB available):**

| Component            | Estimated size |
| -------------------- | -------------- |
| Current usage        | ~80 KB         |
| lwIP heap + pbufs    | ~16 KB         |
| CYW43 driver buffers | ~8 KB          |
| DMA buffers          | ~2 KB          |
| **Total**            | **~106 KB**    |

Comfortable fit within 520 KB SRAM. ~414 KB headroom.

---

## Boot Flow (Modified)

```
resetHandler()
  ├── Zero .bss, copy .data (unchanged)
  └── main()
        ├── hal.initClocks()                          (unchanged)
        │
        ├── if (!hal.isTimerRunning())                (modified condition)
        │     ├── wifi.init()                         [NEW] Init PIO SPI, power on CYW43
        │     ├── wifi.connect(ssid, password)        [NEW] WPA2 association + DHCP
        │     ├── ntp.syncTime()                      [NEW] Single NTP request → set POWMAN timer
        │     ├── wifi.disconnect()                   [NEW] Disconnect, power off CYW43
        │     └── hal.startTimer()                    (unchanged)
        │
        ├── hal.initSpi()                             (unchanged, display SPI)
        ├── readTime() → render → display.refresh()   (unchanged)
        ├── hal.setAlarm(now + 5min)                  (unchanged)
        ├── hal.useLposc() → hal.enterDormant()       (unchanged)
        └── hal.softReset()                           (unchanged)
```

WiFi is only active during the first boot after power loss. On subsequent wake cycles, the POWMAN
timer is already running and keeps time across dormant/reset cycles. An optional periodic re-sync
(e.g. once per day) could be added later.

---

## Build System Changes

The Zig build system needs to compile C sources for the CYW43 driver and lwIP. Zig's
`addCSourceFiles` handles this natively — no CMake or Makefile needed.

```zig
// In buildInkyPicoBinary():
exe.addCSourceFiles(.{
    .files = &.{
        "vendor/cyw43-driver/src/cyw43_ctrl.c",
        "vendor/cyw43-driver/src/cyw43_ll.c",
        "vendor/cyw43-driver/src/cyw43_lwip.c",
        "vendor/cyw43-driver/src/cyw43_spi.c",
        // lwIP core
        "vendor/lwip/src/core/init.c",
        "vendor/lwip/src/core/mem.c",
        "vendor/lwip/src/core/memp.c",
        "vendor/lwip/src/core/pbuf.c",
        "vendor/lwip/src/core/udp.c",
        "vendor/lwip/src/core/dns.c",
        "vendor/lwip/src/core/sys.c",
        "vendor/lwip/src/core/netif.c",
        "vendor/lwip/src/core/timeouts.c",
        "vendor/lwip/src/core/inet_chksum.c",
        "vendor/lwip/src/core/ip.c",
        "vendor/lwip/src/core/def.c",
        // lwIP IPv4
        "vendor/lwip/src/core/ipv4/ip4.c",
        "vendor/lwip/src/core/ipv4/ip4_addr.c",
        "vendor/lwip/src/core/ipv4/etharp.c",
        "vendor/lwip/src/core/ipv4/dhcp.c",
        "vendor/lwip/src/core/ipv4/icmp.c",
        // lwIP netif
        "vendor/lwip/src/netif/ethernet.c",
    },
    .flags = &.{ "-nostdlib", "-fno-builtin" },
});

exe.addIncludePath(.{ .cwd_relative = "vendor/cyw43-driver/src" });
exe.addIncludePath(.{ .cwd_relative = "vendor/cyw43-driver/firmware" });
exe.addIncludePath(.{ .cwd_relative = "vendor/lwip/src/include" });
exe.addIncludePath(.{ .cwd_relative = "bin/inky-pico/lwip" }); // lwipopts.h, cyw43_configport.h
```

**Vendor dependencies (git submodules or copied sources):**

```
vendor/
├── cyw43-driver/    # https://github.com/georgerobotics/cyw43-driver
│   ├── src/         # Driver C sources
│   └── firmware/    # Firmware blobs (header files)
└── lwip/            # https://github.com/lwip-tcpip/lwip
    └── src/         # lwIP C sources
```

---

## New Files

```
bin/inky-pico/
├── main.zig              (modified: add WiFi/NTP sync before render)
├── hal.zig               (modified: add gpioRead, PIO init, DMA helpers)
├── wifi.zig              [NEW] CYW43 init/connect/disconnect, HAL glue callbacks
├── ntp.zig               [NEW] SNTP client (~50 lines)
├── pio_spi.zig           [NEW] PIO SPI transport for CYW43
├── lwip/
│   ├── lwipopts.h        [NEW] lwIP configuration
│   ├── cyw43_configport.h [NEW] CYW43 driver configuration overrides
│   └── sys_arch.c        [NEW] lwIP sys_arch stubs (sys_now only)
├── boot.zig              (unchanged)
├── display.zig           (unchanged)
└── link.ld               (unchanged)
```

---

## Implementation Order

### Phase 1: Build infrastructure

1. Add `vendor/` with cyw43-driver and lwIP sources (git submodules or copy)
2. Create `lwipopts.h` and `cyw43_configport.h` with minimal configuration
3. Update `build.zig` to compile C sources for the inky-pico target
4. Create stub implementations for all HAL callbacks (return 0 / no-op)
5. Verify the project compiles without link errors

### Phase 2: PIO SPI transport

1. Add PIO block initialization to `hal.zig` (claim PIO0 SM0, load program, configure pins)
2. Implement the half-duplex SPI PIO program (port from Pico SDK or embed pre-assembled)
3. Add DMA channel setup for TX/RX with byte-swap
4. Implement `cyw43_spi_init`, `cyw43_spi_transfer`, and related functions in `pio_spi.zig`
5. Test: verify SPI communication by reading the CYW43 test register at address 0x14 (should return
   `0xFEEDBEAD`)

### Phase 3: CYW43 driver integration

1. Implement all HAL callbacks in `wifi.zig` (timing, GPIO, MAC address)
2. Implement lwIP network callbacks (`cyw43_cb_tcpip_init/deinit/set_link_up/down`)
3. Call `cyw43_init()` → `cyw43_wifi_set_up()` → verify firmware upload completes
4. Call `cyw43_wifi_join()` with SSID/key/auth, poll `cyw43_tcpip_link_status()` in a loop (calling
   `cyw43_ll_process_packets()` + `sys_check_timeouts()` each iteration) until `CYW43_LINK_UP` →
   verify WiFi association + DHCP

### Phase 4: NTP sync

1. Implement `ntp.zig`: create UDP PCB, send request, parse response, set POWMAN timer
2. Wire into `main.zig`: sync on first boot, then proceed with normal render cycle
3. Add WiFi credential build options to `build.zig`
4. End-to-end test: build, flash, verify correct time on display

### Phase 5: Polish

1. Add timeout handling (WiFi connect timeout, NTP response timeout)
2. Add fallback: if WiFi/NTP fails, use build-time timestamp (current behavior)
3. Optional: periodic re-sync (e.g. once per 24 hours) to correct LPOSC drift
4. Update `docs/pi-pico-2-setup.md` for Pico 2 W variant
5. Power off CYW43 completely after sync to minimize sleep current

---

## Risk Assessment

| Risk                                | Likelihood | Mitigation                                         |
| ----------------------------------- | ---------- | -------------------------------------------------- |
| PIO SPI timing issues               | Medium     | Start with slow clock, validate with test register |
| CYW43 firmware upload failure       | Low        | Well-tested path in Pico SDK, same hardware        |
| Flash overflow from firmware blob   | None       | 754 KB << 4 MB available                           |
| Display SPI conflict with CYW43     | None       | Completely separate pins and peripherals           |
| DMA channel conflict                | Low        | RP2350 has 16 DMA channels, plenty available       |
| WiFi not available at boot location | Medium     | Fallback to build-time timestamp                   |
| WPA2 auth adds crypto code size     | Low        | Handled inside CYW43 firmware, not our binary      |
| lwIP memory fragmentation           | Low        | Pool allocator with fixed-size pbufs               |
| Power consumption during WiFi sync  | None       | Only active for a few seconds, then fully off      |

---

## References

- [cyw43-driver](https://github.com/georgerobotics/cyw43-driver) — CYW43439 driver
- [lwIP](https://github.com/lwip-tcpip/lwip) — Lightweight IP stack
- [Pico SDK CYW43 bus driver](https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/pico_cyw43_driver/cyw43_bus_pio_spi.c)
  — Reference PIO SPI implementation
- [Pico SDK PIO program](https://github.com/raspberrypi/pico-sdk/blob/master/src/rp2_common/pico_cyw43_driver/cyw43_bus_pio_spi.pio)
  — PIO assembly source
- [Pico 2 W board header](https://github.com/raspberrypi/pico-sdk/blob/master/src/boards/include/boards/pico2_w.h)
  — Pin definitions
- [PicoWi part 1: low-level interface](https://iosoft.blog/2022/12/06/picowi_part1/) — Excellent
  gSPI protocol walkthrough
- [CYW43439 datasheet](https://www.mouser.com/datasheet/2/196/Infineon_CYW43439_DataSheet_v03_00_EN-3074791.pdf)
  — Official Infineon datasheet
- [Pico W NTP example](https://github.com/raspberrypi/pico-examples/tree/master/pico_w/wifi/ntp_client)
  — Reference NTP implementation
