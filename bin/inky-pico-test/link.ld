ENTRY(vector_table)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x10000000, LENGTH = 4M
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 520K
}

SECTIONS
{
    .image_def :
    {
        KEEP(*(.image_def))
    } > FLASH

    .vector_table ALIGN(256) :
    {
        KEEP(*(.vector_table))
    } > FLASH

    .text :
    {
        *(.text .text.*)
    } > FLASH

    .rodata :
    {
        *(.rodata .rodata.*)
    } > FLASH

    /DISCARD/ :
    {
        *(.ARM.exidx .ARM.exidx.*)
        *(.ARM.extab .ARM.extab.*)
    }

    .data :
    {
        _data_start = .;
        *(.data .data.*)
        _data_end = .;
    } > SRAM AT > FLASH

    _data_load = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        _bss_end = .;
    } > SRAM
}
