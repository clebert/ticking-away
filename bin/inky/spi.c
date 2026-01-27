#include "spi.h"
#include <fcntl.h>
#include <unistd.h>
#ifdef __linux__
#include <linux/spi/spi.h>
#include <linux/spi/spidev.h>
#include <sys/ioctl.h>

int spi_init(SPIDevice *dev, const char *device, uint32_t speed_hz) {
  dev->fd = open(device, O_RDWR);
  if (dev->fd < 0) {
    return -1;
  }

  dev->speed_hz = speed_hz;

  uint8_t mode = SPI_MODE_0;
  if (ioctl(dev->fd, SPI_IOC_WR_MODE, &mode) < 0) {
    (void)close(dev->fd);
    dev->fd = -1;
    return -1;
  }

  uint8_t bits = 8;
  if (ioctl(dev->fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0) {
    (void)close(dev->fd);
    dev->fd = -1;
    return -1;
  }

  if (ioctl(dev->fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed_hz) < 0) {
    (void)close(dev->fd);
    dev->fd = -1;
    return -1;
  }

  return 0;
}

int spi_transfer(SPIDevice *dev, const uint8_t *tx, size_t len) {
  if (dev->fd < 0) {
    return -1;
  }

  // Chunk transfers to stay within spidev buffer limit (default 4096 bytes)
  enum { CHUNK_SIZE = 4096 };
  size_t offset = 0;

  while (offset < len) {
    size_t chunk_len = len - offset;
    if (chunk_len > CHUNK_SIZE) {
      chunk_len = CHUNK_SIZE;
    }

    struct spi_ioc_transfer tr = {0};
    tr.tx_buf = (unsigned long)(tx + offset);
    tr.rx_buf = 0;
    tr.len = (uint32_t)chunk_len;
    tr.speed_hz = dev->speed_hz;
    tr.bits_per_word = 8;

    if (ioctl(dev->fd, SPI_IOC_MESSAGE(1), &tr) < 0) {
      return -1;
    }

    offset += chunk_len;
  }

  return 0;
}

void spi_cleanup(SPIDevice *dev) {
  if (dev->fd >= 0) {
    (void)close(dev->fd);
    dev->fd = -1;
  }
}

#else

int spi_init(SPIDevice *dev, const char *device, uint32_t speed_hz) {
  (void)dev;
  (void)device;
  (void)speed_hz;
  return -1;
}

int spi_transfer(SPIDevice *dev, const uint8_t *tx, size_t len) {
  (void)dev;
  (void)tx;
  (void)len;
  return -1;
}

void spi_cleanup(SPIDevice *dev) { (void)dev; }

#endif
