OBJS = \
	src/krnl/bio.o\
	src/krnl/console.o\
	src/krnl/exec.o\
	src/krnl/file.o\
	src/krnl/fs.o\
	src/krnl/ide.o\
	src/krnl/ioapic.o\
	src/krnl/kalloc.o\
	src/krnl/kbd.o\
	src/krnl/lapic.o\
	src/krnl/log.o\
	src/krnl/main.o\
	src/krnl/mp.o\
	src/krnl/picirq.o\
	src/krnl/pipe.o\
	src/krnl/proc.o\
	src/krnl/spinlock.o\
	src/krnl/string.o\
	src/krnl/swtch.o\
	src/krnl/syscall.o\
	src/krnl/sysfile.o\
	src/krnl/sysproc.o\
	src/krnl/timer.o\
	src/krnl/trapasm.o\
	src/krnl/trap.o\
	src/krnl/uart.o\
	src/krnl/vectors.o\
	src/krnl/vm.o\

# Cross-compiling (e.g., on Mac OS X)
#TOOLPREFIX = i386-jos-elf-

# Using native tools (e.g., on X86 Linux)
#TOOLPREFIX = 

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# If the makefile can't find QEMU, specify its path here
#QEMU = 

# Try to infer the correct QEMU
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1)
endif

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gcc
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
#CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer
CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer -Iinclude
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)
ASFLAGS = -m32 -gdwarf-2 -x assembler-with-cpp -Iinclude
# FreeBSD ld wants ``elf_i386_fbsd''
LDFLAGS = -m $(shell $(LD) -V | grep elf_i386 2>/dev/null)

all: xv6.img

xv6.img: bootblock kernel fs.img
	dd if=/dev/zero of=xv6.img count=10000
	dd if=bootblock of=xv6.img conv=notrunc
	dd if=kernel of=xv6.img seek=1 conv=notrunc

xv6memfs.img: bootblock kernelmemfs
	dd if=/dev/zero of=xv6memfs.img count=10000
	dd if=bootblock of=xv6memfs.img conv=notrunc
	dd if=kernelmemfs of=xv6memfs.img seek=1 conv=notrunc

bootblock: src/boot/bootasm.S src/boot/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -O -nostdinc -c src/boot/bootmain.c -o src/boot/bootmain.o
	$(AS) $(ASFLAGS) -fno-pic -nostdinc -c src/boot/bootasm.S -o src/boot/bootasm.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o src/boot/bootblock.o src/boot/bootasm.o src/boot/bootmain.o
	$(OBJDUMP) -S src/boot/bootblock.o > src/boot/bootblock.asm
	$(OBJCOPY) -S -O binary -j .text src/boot/bootblock.o src/boot/bootblock
	./sign.pl src/boot/bootblock

%.o: %.S
	$(AS) $(ASFLAGS) -c $^ -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $^ -o $@

src/boot/entryother: src/boot/entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -c src/boot/entryother.S -o src/boot/entryother.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o src/boot/bootblockother.o src/boot/entryother.o
	$(OBJCOPY) -S -O binary -j .text src/boot/bootblockother.o src/boot/entryother
	$(OBJDUMP) -S src/boot/bootblockother.o > src/boot/entryother.asm

src/krnl/initcode: src/krnl/initcode.S
	$(CC) $(CFLAGS) -nostdinc -c src/krnl/initcode.S -o src/krnl/initcode.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o src/krnl/initcode.out src/krnl/initcode.o
	$(OBJCOPY) -S -O binary src/krnl/initcode.out src/krnl/initcode
	$(OBJDUMP) -S src/krnl/initcode.o > src/krnl/initcode.asm

kernel: $(OBJS) src/boot/entry.o src/boot/entryother src/krnl/initcode kernel.ld
	$(LD) $(LDFLAGS) -T kernel.ld -o kernel src/boot/entry.o $(OBJS) -b binary src/krnl/initcode src/boot/entryother
	$(OBJDUMP) -S kernel > kernel.asm
	$(OBJDUMP) -t kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernel.sym

# kernelmemfs is a copy of kernel that maintains the
# disk image in memory instead of writing to a disk.
# This is not so useful for testing persistent storage or
# exploring disk buffering implementations, but it is
# great for testing the kernel on real hardware without
# needing a scratch disk.
MEMFSOBJS = $(filter-out ide.o,$(OBJS)) memide.o
kernelmemfs: $(MEMFSOBJS) entry.o entryother initcode fs.img
	$(LD) $(LDFLAGS) -Ttext 0x100000 -e main -o kernelmemfs entry.o  $(MEMFSOBJS) -b binary initcode entryother fs.img
	$(OBJDUMP) -S kernelmemfs > kernelmemfs.asm
	$(OBJDUMP) -t kernelmemfs | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernelmemfs.sym

tags: $(OBJS) src/boot/entryother.S _init
	etags *.S *.c

#vectors.S: vectors.pl
#	perl vectors.pl > vectors.S

ULIB = src/lib/user/ulib.o src/lib/user/usys.o src/lib/user/printf.o src/lib/user/umalloc.o

_%: src/user/%.o $(ULIB)
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^
	$(OBJDUMP) -S $@ > $*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $*.sym

_forktest: forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o _forktest forktest.o ulib.o usys.o
	$(OBJDUMP) -S _forktest > forktest.asm

mkfs: mkfs.c fs.h
	gcc -m32 -Werror -Wall -o mkfs mkfs.c

UPROGS=\
	_cat\
	_echo\
	_forktest\
	_grep\
	_init\
	_kill\
	_ln\
	_ls\
	_mkdir\
	_rm\
	_sh\
	_stressfs\
	_usertests\
	_wc\
	_zombie\

fs.img: mkfs README $(UPROGS)
	./mkfs fs.img README $(UPROGS)

-include *.d

clean: 
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	*.o *.d *.asm *.sym vectors.S bootblock entryother \
	initcode initcode.out kernel xv6.img fs.img kernelmemfs mkfs \
	.gdbinit \
	$(UPROGS)
	@find ./src -name '*.o'   -delete
	@find ./src -name '*.lib' -delete
	@find ./src -name '*.exe' -delete
	@find ./src -name '*.d'   -delete

# make a printout
FILES = $(shell grep -v '^\#' runoff.list)
PRINT = runoff.list runoff.spec README toc.hdr toc.ftr $(FILES)

xv6.pdf: $(PRINT)
	./runoff
	ls -l xv6.pdf

print: xv6.pdf

# run in emulators

bochs : fs.img xv6.img
	if [ ! -e .bochsrc ]; then ln -s dot-bochsrc .bochsrc; fi
	bochs -q

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
ifndef CPUS
CPUS := 2
endif
QEMUOPTS = -hdb fs.img xv6.img -smp $(CPUS) -m 512 $(QEMUEXTRA)

qemu: fs.img xv6.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)

qemu-memfs: xv6memfs.img
	$(QEMU) xv6memfs.img -smp $(CPUS)

qemu-nox: fs.img xv6.img
	$(QEMU) -nographic $(QEMUOPTS)

.gdbinit: .gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

qemu-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -serial mon:stdio $(QEMUOPTS) -S $(QEMUGDB)

qemu-nox-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -nographic $(QEMUOPTS) -S $(QEMUGDB)

.PHONY: dist-test dist
