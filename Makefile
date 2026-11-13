# Apple II+ C library for cc65
#
#   make            build lib/apple2-dos33.lib
#   make test       also build the test programs
#
# lib/apple2-dos33.lib is a complete replacement for cc65's apple2.lib:
# a copy of the installed one with the DOS 3.3 modules in place of the
# stock modules of the same name. Build a program for DOS 3.3 with:
#   cl65 -t apple2 -I include -o prog prog.c lib/apple2-dos33.lib
# (-I include selects the DOS 3.3 dirent.h; it's needed only for
# directory functions.)
#
# A library of only the replacement modules isn't enough: ld65 scans each
# library once, so a stock module reached through another stock module
# (fopen -> open, remove -> _sysremove) would be resolved from apple2.lib.
# Rebuild after updating cc65, so the stock modules match the toolchain.

CA65   ?= ca65
AR65   ?= ar65
CL65   ?= cl65
TARGET := apple2

# Directory holding the installed cc65 libraries
CC65_LIB  ?= $(shell $(CL65) --print-target-path)/../lib
STOCK_LIB := $(CC65_LIB)/$(TARGET).lib

DOS33_SRC := $(wildcard libsrc/dos33/*.s)
DOS33_OBJ := $(patsubst libsrc/dos33/%.s,build/dos33/%.o,$(DOS33_SRC))
DOS33_INC := $(wildcard libsrc/dos33/*.inc)
DOS33_LIB := lib/apple2-dos33.lib

.PHONY: all test clean

all: $(DOS33_LIB)

build/dos33/%.o: libsrc/dos33/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

$(DOS33_LIB): $(DOS33_OBJ) $(STOCK_LIB)
	@mkdir -p $(@D)
	cp $(STOCK_LIB) $@
	$(AR65) r $@ $(DOS33_OBJ)

test: build/test/filetest

build/test/filetest: test/filetest.c test/irqtest.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/filetest.c test/irqtest.s $(DOS33_LIB)

clean:
	rm -rf build lib
