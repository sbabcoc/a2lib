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
# lib/apple2-dos33-vt.lib adds the Videx VideoTerm backend: conio and
# console output use the card in slot 3 when present, and the stock
# 40-column screen otherwise. Link with it instead of apple2-dos33.lib.
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

VT_SRC := $(wildcard libsrc/vt/*.s)
VT_OBJ := $(patsubst libsrc/vt/%.s,build/vt/%.o,$(VT_SRC))
VT_INC := $(wildcard libsrc/vt/*.inc)
VT_LIB := lib/apple2-dos33-vt.lib

.PHONY: all test clean

all: $(DOS33_LIB) $(VT_LIB)

build/dos33/%.o: libsrc/dos33/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

$(DOS33_LIB): $(DOS33_OBJ) $(STOCK_LIB)
	@mkdir -p $(@D)
	cp $(STOCK_LIB) $@
	$(AR65) r $@ $(DOS33_OBJ)

# VideoTerm backend: apple2-dos33.lib with VideoTerm-aware conio modules
build/vt/%.o: libsrc/vt/%.s $(VT_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/vt -o $@ $<

$(VT_LIB): $(VT_OBJ) $(DOS33_LIB)
	@mkdir -p $(@D)
	cp $(DOS33_LIB) $@
	$(AR65) r $@ $(VT_OBJ)

test: build/test/filetest build/test/vttest

build/test/filetest: test/filetest.c test/irqtest.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/filetest.c test/irqtest.s $(DOS33_LIB)

build/test/vttest: test/vttest.c $(VT_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(VT_LIB)

clean:
	rm -rf build lib
