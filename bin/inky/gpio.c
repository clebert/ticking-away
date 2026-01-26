#include "gpio.h"
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#ifdef __linux__
#include <linux/gpio.h>
#include <sys/ioctl.h>

int gpio_init(GPIOPin *pin, int bcm_number, int direction) {
  pin->chip_fd = open("/dev/gpiochip0", O_RDWR);
  if (pin->chip_fd < 0) {
    return -1;
  }

  pin->line = bcm_number;
  pin->direction = direction;

  struct gpio_v2_line_request req = {0};
  req.offsets[0] = (uint32_t)bcm_number;
  req.num_lines = 1;
  if (direction == GPIO_OUTPUT) {
    req.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
  } else {
    req.config.flags = GPIO_V2_LINE_FLAG_INPUT;
  }
  strncpy(req.consumer, "inky", sizeof(req.consumer) - 1);

  if (ioctl(pin->chip_fd, GPIO_V2_GET_LINE_IOCTL, &req) < 0) {
    (void)close(pin->chip_fd);
    pin->chip_fd = -1;
    return -1;
  }

  pin->req_fd = req.fd;
  return 0;
}

int gpio_write(GPIOPin *pin, int value) {
  if (pin->req_fd < 0) {
    return -1;
  }

  struct gpio_v2_line_values vals = {0};
  vals.mask = 1;
  vals.bits = value ? 1 : 0;

  if (ioctl(pin->req_fd, GPIO_V2_LINE_SET_VALUES_IOCTL, &vals) < 0) {
    return -1;
  }

  return 0;
}

int gpio_read(GPIOPin *pin) {
  if (pin->req_fd < 0) {
    return -1;
  }

  struct gpio_v2_line_values vals = {0};
  vals.mask = 1;

  if (ioctl(pin->req_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &vals) < 0) {
    return -1;
  }

  return (vals.bits & 1) ? 1 : 0;
}

void gpio_cleanup(GPIOPin *pin) {
  if (pin->req_fd >= 0) {
    (void)close(pin->req_fd);
    pin->req_fd = -1;
  }
  if (pin->chip_fd >= 0) {
    (void)close(pin->chip_fd);
    pin->chip_fd = -1;
  }
}

#else

int gpio_init(GPIOPin *pin, int bcm_number, int direction) {
  (void)pin;
  (void)bcm_number;
  (void)direction;
  return -1;
}

int gpio_write(GPIOPin *pin, int value) {
  (void)pin;
  (void)value;
  return -1;
}

int gpio_read(GPIOPin *pin) {
  (void)pin;
  return -1;
}

void gpio_cleanup(GPIOPin *pin) { (void)pin; }

#endif
