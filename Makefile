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
# lib/apple2-dos33-vtwin.lib uses the VideoTerm when present and, without
# it, a 40-column window onto an 80 x 24 screen (include/c40win.h).
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

WIN_SRC := $(wildcard libsrc/win/*.s)
WIN_OBJ := $(patsubst libsrc/win/%.s,build/win/%.o,$(WIN_SRC))
WIN_INC := $(wildcard libsrc/win/*.inc)
VTWIN_LIB := lib/apple2-dos33-vtwin.lib

.PHONY: all test simtest clean

IP65_OBJ := lib/a2lib-ip65.o

all: $(DOS33_LIB) $(VT_LIB) $(VTWIN_LIB) $(IP65_OBJ)

build/dos33/%.o: libsrc/dos33/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

$(DOS33_LIB): $(DOS33_OBJ) $(STOCK_LIB)
	@mkdir -p $(@D)
	cp $(STOCK_LIB) $@
	$(AR65) r $@ $(DOS33_OBJ)

# VideoTerm backend: apple2-dos33.lib with VideoTerm-aware conio modules
build/vt/%.o: libsrc/vt/%.s $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/vt -I libsrc/dos33 -o $@ $<

$(VT_LIB): $(VT_OBJ) $(DOS33_LIB)
	@mkdir -p $(@D)
	cp $(DOS33_LIB) $@
	$(AR65) r $@ $(VT_OBJ)

# IP65 timer driver on the cooperative timer: an object file, listed on the
# link line before IP65's library (libsrc/ip65/a2timer.s)
$(IP65_OBJ): libsrc/ip65/a2timer.s libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

# VideoTerm backend with the 40-column window as its fallback: vt.s and the
# window's conio modules (which include the VideoTerm paths)
build/win/%.o: libsrc/win/%.s $(WIN_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/win -I libsrc/vt -I libsrc/dos33 -o $@ $<

$(VTWIN_LIB): $(WIN_OBJ) build/vt/vt.o $(DOS33_LIB)
	@mkdir -p $(@D)
	cp $(DOS33_LIB) $@
	$(AR65) r $@ build/vt/vt.o $(WIN_OBJ)

test: build/test/filetest build/test/vttest build/test/wintest build/test/timertest build/test/cswtest build/test/cswwtest

build/test/filetest: test/filetest.c test/irqtest.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/filetest.c test/irqtest.s $(DOS33_LIB)

build/test/vttest: test/vttest.c $(VT_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(VT_LIB)

build/test/wintest: test/vttest.c $(VTWIN_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DC40WIN -m $@.map -o $@ $< $(VTWIN_LIB)

build/test/cswtest: test/cswtest.c test/cswcout.s $(VT_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/cswtest.c test/cswcout.s $(VT_LIB)

build/test/cswwtest: test/cswtest.c test/cswcout.s $(VTWIN_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DC40WIN -m $@.map -o $@ test/cswtest.c test/cswcout.s $(VTWIN_LIB)

build/test/timertest: test/timertest.c test/timerzp.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/timertest.c test/timerzp.s $(DOS33_LIB)

# Regression tests that run in cc65's 6502 simulator, sim65, without an
# Apple II: the timer modules and the window's gauge, built for sim6502.
SIM_DIR  := build/sim
SIM_MODS := timer tick kbhit gettime settime
SIM_OBJ  := $(patsubst %,$(SIM_DIR)/%.o,$(SIM_MODS))
SIM65    ?= sim65

$(SIM_DIR)/%.o: libsrc/dos33/%.s libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 -I libsrc/dos33 -o $@ $<

$(SIM_DIR)/win.o: libsrc/win/win.s $(WIN_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 -I libsrc/win -I libsrc/vt -I libsrc/dos33 -o $@ $<

$(SIM_DIR)/timersim: test/sim/timersim.c test/sim/shim.s test/timerzp.s $(SIM_OBJ)
	$(CL65) -t sim6502 -O -I include -o $@ $^

$(SIM_DIR)/gaugesim: test/sim/gaugesim.c test/sim/shim.s test/sim/winshim.s $(SIM_DIR)/win.o $(SIM_OBJ)
	$(CL65) -t sim6502 -C test/sim/sim0c00.cfg -O -I include -o $@ $^

simtest: $(SIM_DIR)/timersim $(SIM_DIR)/gaugesim
	$(SIM65) $(SIM_DIR)/timersim
	$(SIM65) $(SIM_DIR)/gaugesim

clean:
	rm -rf build lib
