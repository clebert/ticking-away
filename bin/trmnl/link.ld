ENTRY(_start)

/* The ESP32-C3's 400 KB internal SRAM is one physical block aliased onto two
   buses (instruction-bus IRAM address = data-bus DRAM address + 0x700000), so
   code and data must occupy DISJOINT physical ranges. Split that one SRAM:
   code through the IRAM alias at 0x40380000 (= physical 0x3FC80000), data
   through the DRAM alias at 0x3FC90000 (= IRAM 0x40390000). The two windows do
   not overlap. Stack tops out at 0x3FCC0000, well below the ROM-reserved area. */
MEMORY {
  IRAM (rwx) : ORIGIN = 0x40380000, LENGTH = 64K
  DRAM (rw)  : ORIGIN = 0x3FC90000, LENGTH = 192K
}

SECTIONS {
  .text : {
    KEEP(*(.text._start))
    *(.text .text.*)
  } > IRAM

  .rodata : {
    *(.rodata .rodata.* .srodata .srodata.*)
  } > DRAM

  .data : {
    . = ALIGN(8);
    PROVIDE(__global_pointer$ = . + 0x800);
    *(.sdata .sdata.* .data .data.*)
  } > DRAM

  .bss (NOLOAD) : {
    . = ALIGN(8);
    *(.sbss .sbss.* .bss .bss.* COMMON)
  } > DRAM

  PROVIDE(__stack_top = ORIGIN(DRAM) + LENGTH(DRAM));
}
