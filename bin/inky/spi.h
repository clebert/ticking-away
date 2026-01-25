#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
  int fd;
  uint32_t speed_hz;
} SPIDevice;

int spi_init(SPIDevice *dev, const char *device, uint32_t speed_hz);
int spi_transfer(SPIDevice *dev, const uint8_t *tx, size_t len);
void spi_cleanup(SPIDevice *dev);
