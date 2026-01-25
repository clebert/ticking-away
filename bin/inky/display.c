#ifdef __linux__
// NOLINTBEGIN(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming)
#define _POSIX_C_SOURCE 199309L
// NOLINTEND(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming)
#endif

#include "display.h"

#ifdef __linux__
#include <time.h>

enum { BCM_RESET = 27, BCM_BUSY = 17, BCM_DC = 22, BCM_CS0 = 26, BCM_CS1 = 16 };

enum {
  CMD_PSR = 0x00,
  CMD_PWR = 0x01,
  CMD_POF = 0x02,
  CMD_PON = 0x04,
  CMD_BTST_N = 0x05,
  CMD_BTST_P = 0x06,
  CMD_DTM = 0x10,
  CMD_DRF = 0x12,
  CMD_PLL = 0x30,
  CMD_CDI = 0x50,
  CMD_TCON = 0x60,
  CMD_TRES = 0x61,
  CMD_ANTM = 0x74,
  CMD_AGID = 0x86,
  CMD_BUCK_VDDN = 0xB0,
  CMD_TFT_VCOM = 0xB1,
  CMD_EN_BUF = 0xB6,
  CMD_BOOST_VDDP = 0xB7,
  CMD_CCSET = 0xE0,
  CMD_PWS = 0xE3,
  CMD_CMD66 = 0xF0
};

static void delay_ms(uint32_t ms) {
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (ms % 1000) * 1000000L;
  (void)nanosleep(&ts, nullptr);
}

static uint64_t get_time_ms(void) {
  struct timespec ts;
  (void)clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static void busy_wait(InkyDisplay *display, uint32_t timeout_ms) {
  // BUSY pin: HIGH (1) = display busy, LOW (0) = display ready.
  // If GPIO read fails, fall back to a fixed delay.
  if (gpio_read(&display->busy) < 0) {
    delay_ms(timeout_ms);
    return;
  }

  // Poll until BUSY goes LOW (ready) or timeout expires
  uint64_t start = get_time_ms();
  while (gpio_read(&display->busy) == 1) {
    delay_ms(100);
    if (get_time_ms() - start > timeout_ms) {
      break;
    }
  }
}

static void set_cs(InkyDisplay *display, uint8_t cs_sel) {
  int cs0_val = (cs_sel & CS_SEL_CS0) ? 0 : 1;
  int cs1_val = (cs_sel & CS_SEL_CS1) ? 0 : 1;
  (void)gpio_write(&display->cs0, cs0_val);
  (void)gpio_write(&display->cs1, cs1_val);
}

static void deselect_cs(InkyDisplay *display) {
  (void)gpio_write(&display->cs0, 1);
  (void)gpio_write(&display->cs1, 1);
}

static int send_command(InkyDisplay *display, uint8_t cmd, uint8_t cs_sel, const uint8_t *data,
                        size_t len) {
  set_cs(display, cs_sel);

  // Command preamble: DC low signals command mode. The 300ms delay is specified
  // in the EL133UF1 protocol and appears critical for reliable communication.
  (void)gpio_write(&display->dc, 0);
  delay_ms(300);

  if (spi_transfer(&display->spi, &cmd, 1) < 0) {
    deselect_cs(display);
    return -1;
  }

  if (data != nullptr && len > 0) {
    (void)gpio_write(&display->dc, 1);
    if (spi_transfer(&display->spi, data, len) < 0) {
      deselect_cs(display);
      (void)gpio_write(&display->dc, 0);
      return -1;
    }
  }

  deselect_cs(display);
  (void)gpio_write(&display->dc, 0);

  return 0;
}

static int hardware_reset(InkyDisplay *display) {
  (void)gpio_write(&display->reset, 0);
  delay_ms(30);
  (void)gpio_write(&display->reset, 1);
  delay_ms(30);
  busy_wait(display, 300);
  return 0;
}

static int init_sequence(InkyDisplay *display) {
  uint8_t antm_data[] = {0xC0, 0x1C, 0x1C, 0xCC, 0xCC, 0xCC, 0x15, 0x15, 0x55};
  if (send_command(display, CMD_ANTM, CS_SEL_CS0, antm_data, sizeof(antm_data)) < 0) {
    return -1;
  }

  uint8_t cmd66_data[] = {0x49, 0x55, 0x13, 0x5D, 0x05, 0x10};
  if (send_command(display, CMD_CMD66, CS_SEL_BOTH, cmd66_data, sizeof(cmd66_data)) < 0) {
    return -1;
  }

  uint8_t psr_data[] = {0xDF, 0x69};
  if (send_command(display, CMD_PSR, CS_SEL_BOTH, psr_data, sizeof(psr_data)) < 0) {
    return -1;
  }

  uint8_t pll_data[] = {0x08};
  if (send_command(display, CMD_PLL, CS_SEL_BOTH, pll_data, sizeof(pll_data)) < 0) {
    return -1;
  }

  uint8_t cdi_data[] = {0xF7};
  if (send_command(display, CMD_CDI, CS_SEL_BOTH, cdi_data, sizeof(cdi_data)) < 0) {
    return -1;
  }

  uint8_t tcon_data[] = {0x03, 0x03};
  if (send_command(display, CMD_TCON, CS_SEL_BOTH, tcon_data, sizeof(tcon_data)) < 0) {
    return -1;
  }

  uint8_t agid_data[] = {0x10};
  if (send_command(display, CMD_AGID, CS_SEL_BOTH, agid_data, sizeof(agid_data)) < 0) {
    return -1;
  }

  uint8_t pws_data[] = {0x22};
  if (send_command(display, CMD_PWS, CS_SEL_BOTH, pws_data, sizeof(pws_data)) < 0) {
    return -1;
  }

  uint8_t ccset_data[] = {0x01};
  if (send_command(display, CMD_CCSET, CS_SEL_BOTH, ccset_data, sizeof(ccset_data)) < 0) {
    return -1;
  }

  uint8_t tres_data[] = {0x04, 0xB0, 0x03, 0x20};
  if (send_command(display, CMD_TRES, CS_SEL_BOTH, tres_data, sizeof(tres_data)) < 0) {
    return -1;
  }

  uint8_t pwr_data[] = {0x0F, 0x00, 0x28, 0x2C, 0x28, 0x38};
  if (send_command(display, CMD_PWR, CS_SEL_CS0, pwr_data, sizeof(pwr_data)) < 0) {
    return -1;
  }

  uint8_t en_buf_data[] = {0x07};
  if (send_command(display, CMD_EN_BUF, CS_SEL_CS0, en_buf_data, sizeof(en_buf_data)) < 0) {
    return -1;
  }

  uint8_t btst_p_data[] = {0xD8, 0x18};
  if (send_command(display, CMD_BTST_P, CS_SEL_CS0, btst_p_data, sizeof(btst_p_data)) < 0) {
    return -1;
  }

  uint8_t boost_vddp_data[] = {0x01};
  if (send_command(display, CMD_BOOST_VDDP, CS_SEL_CS0, boost_vddp_data, sizeof(boost_vddp_data)) <
      0) {
    return -1;
  }

  uint8_t btst_n_data[] = {0xD8, 0x18};
  if (send_command(display, CMD_BTST_N, CS_SEL_CS0, btst_n_data, sizeof(btst_n_data)) < 0) {
    return -1;
  }

  uint8_t buck_vddn_data[] = {0x01};
  if (send_command(display, CMD_BUCK_VDDN, CS_SEL_CS0, buck_vddn_data, sizeof(buck_vddn_data)) <
      0) {
    return -1;
  }

  uint8_t tft_vcom_data[] = {0x02};
  if (send_command(display, CMD_TFT_VCOM, CS_SEL_CS0, tft_vcom_data, sizeof(tft_vcom_data)) < 0) {
    return -1;
  }

  return 0;
}

int inky_init(InkyDisplay *display) {
  if (spi_init(&display->spi, "/dev/spidev0.0", 10000000) < 0) {
    return -1;
  }

  if (gpio_init(&display->reset, BCM_RESET, GPIO_OUTPUT) < 0) {
    spi_cleanup(&display->spi);
    return -1;
  }

  if (gpio_init(&display->busy, BCM_BUSY, GPIO_INPUT) < 0) {
    gpio_cleanup(&display->reset);
    spi_cleanup(&display->spi);
    return -1;
  }

  if (gpio_init(&display->dc, BCM_DC, GPIO_OUTPUT) < 0) {
    gpio_cleanup(&display->busy);
    gpio_cleanup(&display->reset);
    spi_cleanup(&display->spi);
    return -1;
  }

  if (gpio_init(&display->cs0, BCM_CS0, GPIO_OUTPUT) < 0) {
    gpio_cleanup(&display->dc);
    gpio_cleanup(&display->busy);
    gpio_cleanup(&display->reset);
    spi_cleanup(&display->spi);
    return -1;
  }

  if (gpio_init(&display->cs1, BCM_CS1, GPIO_OUTPUT) < 0) {
    gpio_cleanup(&display->cs0);
    gpio_cleanup(&display->dc);
    gpio_cleanup(&display->busy);
    gpio_cleanup(&display->reset);
    spi_cleanup(&display->spi);
    return -1;
  }

  deselect_cs(display);
  (void)gpio_write(&display->dc, 0);
  (void)gpio_write(&display->reset, 1);

  return 0;
}

int inky_show(InkyDisplay *display, const uint8_t *packed_left, const uint8_t *packed_right) {
  if (hardware_reset(display) < 0) {
    return -1;
  }

  if (init_sequence(display) < 0) {
    return -1;
  }

  if (send_command(display, CMD_DTM, CS_SEL_CS0, packed_left, INKY_BUFFER_SIZE) < 0) {
    return -1;
  }

  if (send_command(display, CMD_DTM, CS_SEL_CS1, packed_right, INKY_BUFFER_SIZE) < 0) {
    return -1;
  }

  if (send_command(display, CMD_PON, CS_SEL_BOTH, nullptr, 0) < 0) {
    return -1;
  }
  busy_wait(display, 200);

  uint8_t drf_data[] = {0x00};
  if (send_command(display, CMD_DRF, CS_SEL_BOTH, drf_data, sizeof(drf_data)) < 0) {
    return -1;
  }
  busy_wait(display, 32000);

  uint8_t pof_data[] = {0x00};
  if (send_command(display, CMD_POF, CS_SEL_BOTH, pof_data, sizeof(pof_data)) < 0) {
    return -1;
  }
  busy_wait(display, 200);

  return 0;
}

void inky_cleanup(InkyDisplay *display) {
  gpio_cleanup(&display->cs1);
  gpio_cleanup(&display->cs0);
  gpio_cleanup(&display->dc);
  gpio_cleanup(&display->busy);
  gpio_cleanup(&display->reset);
  spi_cleanup(&display->spi);
}

#else

int inky_init(InkyDisplay *display) {
  (void)display;
  return -1;
}

int inky_show(InkyDisplay *display, const uint8_t *packed_left, const uint8_t *packed_right) {
  (void)display;
  (void)packed_left;
  (void)packed_right;
  return -1;
}

void inky_cleanup(InkyDisplay *display) { (void)display; }

#endif
