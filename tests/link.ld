/* Program at 0x80000000, tohost at 0x80001000. The RTL memory ignores upper
   address bits, so the image aliases onto its word array (loaded at word 0). */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS {
  . = 0x80000000;
  .text : {
    _start = .;
    *(.text.init)
    *(.text)
    *(.text.*)
    *(.rodata*)
    *(.srodata*)
    *(.data*)
    *(.sdata*)
    *(.bss)
    *(.sbss*)
  }

  .tohost 0x80001000 : {
    tohost = .;
    LONG(0);
    fromhost = .;
    LONG(0);
  }

  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) }
}
