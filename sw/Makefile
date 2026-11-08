# Makefile -- C programs for the nano cores with riscv32-nano-elf-gcc -mnano + picolibc.
#
#   make                         examples/hello for the FPGA subsystem
#   make PROG=hello TARGET=asic  the ASIC subsystem map (boot ROM image, UART console)
#   make PROG=myprog SRCS="a.c b.c"   your own sources
#   make PRINTF=i                picolibc's printf instead of bsp/printf_tiny.c (m minimal 1.4 KiB,
#                                i integer 2.4 KiB, d double 4.8 KiB: for memories over 2 KiB)
#
# Output in build/<TARGET>/: <PROG>.elf .dis .bin, <PROG>.img (2 KiB image), <PROG>.hex,
# <PROG>_{0..3}.hex (FPGA RAM byte lanes). Every instruction is checked against the registers
# the nano cores have (x0, ra, sp, a0..a2).

TARGET ?= fpga
PROG   ?= hello
PRINTF ?= tiny
SRCS   ?= $(wildcard examples/$(PROG)/*.c)
PREFIX ?= $(HOME)/opt/riscv32-nano
CROSS  ?= $(PREFIX)/bin/riscv32-nano-elf-

CC      = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump
SIZE    = $(CROSS)size

ARCH    = -march=rv32e -mabi=ilp32e -mnano
CFLAGS ?= -Os -Wall -Wextra
CFLAGS += $(ARCH) -ffunction-sections -fdata-sections -Ibsp
LDFLAGS = $(ARCH) -nostdlib -T bsp/$(TARGET)/link.ld -Wl,--gc-sections -Wl,--no-warn-rwx-segments
LIBS    = -Wl,--start-group -lc -lgcc -Wl,--end-group

BSP = bsp/crt0.S bsp/stdio.c bsp/$(TARGET)/bsp.c
ifeq ($(PRINTF),tiny)
BSP += bsp/printf_tiny.c
else
LDFLAGS += -Wl,--defsym=vfprintf=__$(PRINTF)_vfprintf
endif
OUT = build/$(TARGET)
ELF = $(OUT)/$(PROG).elf

all: $(OUT)/$(PROG).img

$(ELF): $(SRCS) $(BSP) bsp/bsp.h Makefile bsp/$(TARGET)/link.ld
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(LDFLAGS) $(BSP) $(SRCS) $(LIBS) -o $@
	$(OBJDUMP) -d $@ > $(OUT)/$(PROG).dis
	@bad=$$($(OBJDUMP) -d -M numeric,no-aliases $@ \
	  | awk -F'\t' 'NF >= 4 { s = $$4; sub(/[#<].*/, "", s); print s }' \
	  | grep -oE '\bx[0-9]+\b' | sort -u | grep -vxE 'x(0|1|2|10|11|12)' | tr '\n' ' '); \
	  if [ -n "$$bad" ]; then echo "$@: registers the nano cores do not have: $$bad"; rm -f $@; exit 1; fi
	@$(SIZE) $@

$(OUT)/$(PROG).img: $(ELF)
	$(OBJCOPY) -O binary $< $(OUT)/$(PROG).bin
	python3 tools/mkimage.py $(OUT)/$(PROG).bin $(OUT)/$(PROG)

clean:
	rm -rf build

.PHONY: all clean
