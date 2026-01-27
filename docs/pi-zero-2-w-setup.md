# Pi Zero 2 W Setup

Setup guide for running the watchface on a Raspberry Pi Zero 2 W with an Inky Impression display.

## Hardware

- Raspberry Pi Zero 2 W
- Inky Impression 13.3" (Spectra 6, 1600x1200, 6-color)
- Power supply (5V micro-USB)
- MicroSD card

## Raspberry Pi OS Installation

1. Download Raspberry Pi Imager
2. Flash Raspberry Pi OS Lite (64-bit) to the SD card
3. In the imager settings, configure:
   - Hostname: `watchface`
   - Username: `clebert`
   - Enable SSH with public key authentication
   - WiFi credentials (if using wireless)

## Development Machine Setup (macOS)

### Generate SSH Key (if needed)

```sh
ssh-keygen -t rsa -f ~/.ssh/id_rsa_pi -C "watchface"
```

### Add SSH Key to Keychain

```sh
ssh-add --apple-use-keychain ~/.ssh/id_rsa_pi 2>/dev/null || ssh-add ~/.ssh/id_rsa_pi
```

### Configure SSH

Add to `~/.ssh/config`:

```
Host watchface
  HostName watchface.local
  User clebert
  IdentityFile ~/.ssh/id_rsa_pi
  AddKeysToAgent yes
  UseKeychain yes
  IdentitiesOnly yes
```

### Connect

```sh
ssh watchface
```

## Pi Configuration

### Enable SPI

```sh
sudo sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' /boot/firmware/config.txt
sudo reboot
```

### Install Zig

```sh
sudo apt update && sudo apt upgrade -y
sudo mkdir -p /usr/local/zig
curl -fsSL "https://ziglang.org/download/0.15.2/zig-aarch64-linux-0.15.2.tar.xz" \
  | sudo tar -xJ -C /usr/local/zig --strip-components=1
sudo ln -s /usr/local/zig/zig /usr/local/bin/zig
```

## E-Ink Display Setup

The Inky Impression 13.3" connects via SPI and GPIO. See
[inky-impression-13-protocol.md](inky-impression-13-protocol.md) for the full protocol
specification.

### GPIO Pin Connections

| Function | BCM Pin | Physical Pin |
| -------- | ------- | ------------ |
| RESET    | 27      | 13           |
| BUSY     | 17      | 11           |
| DC       | 22      | 15           |
| CS0      | 26      | 37           |
| CS1      | 16      | 36           |
| MOSI     | 10      | 19           |
| SCLK     | 11      | 23           |

### Verify SPI is Enabled

```sh
ls /dev/spidev*
# Should show: /dev/spidev0.0  /dev/spidev0.1
```

## Running the Watchface

TODO: Add deployment and startup instructions.
