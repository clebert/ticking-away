#pragma once

#include "gpio.h"
#include "spi.h"
#include <stdint.h>

enum { INKY_WIDTH = 1600, INKY_HEIGHT = 1200, INKY_BUFFER_SIZE = 480000 };

enum { CS_SEL_CS0 = 0x01, CS_SEL_CS1 = 0x02, CS_SEL_BOTH = 0x03 };

typedef struct {
  SPIDevice spi;
  GPIOPin reset;
  GPIOPin busy;
  GPIOPin dc;
  GPIOPin cs0;
  GPIOPin cs1;
} InkyDisplay;

int inky_init(InkyDisplay *display);
int inky_show(InkyDisplay *display, const uint8_t *packed_left, const uint8_t *packed_right);
void inky_cleanup(InkyDisplay *display);
