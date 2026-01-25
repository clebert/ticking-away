#pragma once

enum { GPIO_INPUT = 0, GPIO_OUTPUT = 1 };

typedef struct {
  int chip_fd;
  int line;
  int direction;
  int req_fd;
} GPIOPin;

int gpio_init(GPIOPin *pin, int bcm_number, int direction);
int gpio_write(GPIOPin *pin, int value);
int gpio_read(GPIOPin *pin);
void gpio_cleanup(GPIOPin *pin);
