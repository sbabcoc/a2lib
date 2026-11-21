# Apple II+ C library for cc65
#
#   make            build the libraries (below)
#   make test       also build the test programs
#   make simtest    build and run the sim65 tests (no Apple II needed)
#   make linktest   check that functions with no DOS 3.3 version don't link
#   make emutest    run the test programs on ReplicApple2Plus (below)
#   make screenshots  the README's screenshot, from an emutest run
#   make clean      remove build/ and lib/
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
# lib/apple2-dos33-vts70.lib uses the VideoTerm when present and, without
# it, Soft-70: 70 columns of the 80 x 24 screen in hi-res (include/soft70.h).
# Programs that use it are linked with --start-addr 0x4000.
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

# Link-time guards (DESIGN.md 4.2): each replaces the stock ProDOS module
# of the same name, so a call to a function with no DOS 3.3 implementation
# fails to link instead of failing at run time
GUARD_SRC := $(wildcard libsrc/guard/*.s)
GUARD_OBJ := $(patsubst libsrc/guard/%.s,build/guard/%.o,$(GUARD_SRC))

VT_SRC := $(wildcard libsrc/vt/*.s)
VT_OBJ := $(patsubst libsrc/vt/%.s,build/vt/%.o,$(VT_SRC))
VT_INC := $(wildcard libsrc/vt/*.inc)
VT_LIB := lib/apple2-dos33-vt.lib

# The shared 80 x 24 model (libsrc/s80) is assembled once for each backend
# that shows part of it, with that backend's display.inc
S80_SRC := $(wildcard libsrc/s80/*.s)
S80_INC := $(wildcard libsrc/s80/*.inc)

WIN_SRC := $(wildcard libsrc/win/*.s)
WIN_OBJ := $(patsubst libsrc/win/%.s,build/win/%.o,$(WIN_SRC)) \
           $(patsubst libsrc/s80/%.s,build/win/%.o,$(S80_SRC))
WIN_INC := $(wildcard libsrc/win/*.inc) $(S80_INC)
VTWIN_LIB := lib/apple2-dos33-vtwin.lib

.PHONY: emutest screenshots all test simtest linktest clean

S70_SRC := $(wildcard libsrc/s70/*.s)
S70_OBJ := $(patsubst libsrc/s70/%.s,build/s70/%.o,$(S70_SRC)) \
           $(patsubst libsrc/s80/%.s,build/s70/%.o,$(S80_SRC))
S70_INC := $(wildcard libsrc/s70/*.inc) $(S80_INC)
VTS70_LIB := lib/apple2-dos33-vts70.lib

IP65_OBJ := lib/a2lib-ip65.o

# An IP65 checkout (https://github.com/cc65/ip65), for the network test,
# with its TCP library and Uthernet II driver built (make -C ip65
# ip65_tcp.lib; make -C drivers a2uther2.lib). Without IP65=, make test
# leaves the network test out.
IP65 ?=
IP65_LIBS = $(IP65)/ip65/ip65_tcp.lib $(IP65)/drivers/a2uther2.lib
NET_TEST := $(if $(IP65),build/test/nettest)

all: $(DOS33_LIB) $(VT_LIB) $(VTWIN_LIB) $(VTS70_LIB) $(IP65_OBJ)

build/dos33/%.o: libsrc/dos33/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

build/guard/%.o: libsrc/guard/%.s
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -o $@ $<

$(DOS33_LIB): $(DOS33_OBJ) $(GUARD_OBJ) $(STOCK_LIB)
	@mkdir -p $(@D)
	cp $(STOCK_LIB) $@
	$(AR65) r $@ $(DOS33_OBJ) $(GUARD_OBJ)

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
WIN_FLAGS := -I libsrc/win -I libsrc/s80 -I libsrc/vt -I libsrc/dos33

build/win/%.o: libsrc/win/%.s $(WIN_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) $(WIN_FLAGS) -o $@ $<

build/win/%.o: libsrc/s80/%.s $(WIN_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) $(WIN_FLAGS) -o $@ $<

$(VTWIN_LIB): $(WIN_OBJ) build/vt/vt.o $(DOS33_LIB)
	@mkdir -p $(@D)
	cp $(DOS33_LIB) $@
	$(AR65) r $@ build/vt/vt.o $(WIN_OBJ)

# Soft-70 with the VideoTerm: vt.s and Soft-70's modules, on the shared
# 80 x 24 model. Programs are linked with --start-addr 0x4000.
S70_FLAGS := -I libsrc/s70 -I libsrc/s80 -I libsrc/vt -I libsrc/dos33

build/s70/%.o: libsrc/s70/%.s $(S70_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) $(S70_FLAGS) -o $@ $<

build/s70/%.o: libsrc/s80/%.s $(S70_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) $(S70_FLAGS) -o $@ $<

# The default font, generated from its source (tools/s70font.txt)
libsrc/s70/font.s: tools/s70font.txt tools/s70font.py
	python3 tools/s70font.py $< $@

$(VTS70_LIB): $(S70_OBJ) build/vt/vt.o $(DOS33_LIB)
	@mkdir -p $(@D)
	cp $(DOS33_LIB) $@
	$(AR65) r $@ build/vt/vt.o $(S70_OBJ)

S70_LINK := --start-addr 0x4000

# Runs the test programs on ReplicApple2Plus's headless runner (DESIGN.md
# 8): make emutest MASTER=path/to/DOS-3.3-System-Master.woz [RUNS="..."]
# RUNNER and AC name the runner and AppleCommander, if not on PATH. The
# network run also needs IP65= (above) and UTHERNET2=, the folder holding
# the Uthernet2 plug-in jar; without them it's skipped.
emutest: test
	bash test/emutest.sh $(RUNS)

# The README's screenshot: S70TEST's last screen on Soft-70, on a green
# monitor, into docs/images. Takes what emutest takes, and ReplicApple2Plus
# 1.11.0's runner or later (its --snap).
screenshots: test
	SNAP=docs/images bash test/emutest.sh s70test

test: build/test/filetest build/test/vttest build/test/wintest build/test/timertest build/test/cswtest build/test/cswwtest \
      build/test/reflowtest build/test/reflowvt build/test/reflowwin \
      build/test/s70test build/test/cswstest build/test/reflows70 $(NET_TEST) \
      build/test/bloadprobe build/test/errprobe build/test/errproberaw \
      build/test/exectest build/test/exectestvt build/test/execatest build/test/argtest

build/test/filetest: test/filetest.c test/irqtest.s test/cswcout.s test/coutcount.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/filetest.c test/irqtest.s test/cswcout.s test/coutcount.s $(DOS33_LIB)

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

build/test/reflowtest: test/reflowtest.c $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(DOS33_LIB)

build/test/reflowvt: test/reflowtest.c $(VT_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(VT_LIB)

build/test/reflowwin: test/reflowtest.c $(VTWIN_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DC40WIN -m $@.map -o $@ $< $(VTWIN_LIB)

build/test/s70test: test/vttest.c $(VTS70_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) $(S70_LINK) -O -I include -DS70 -m $@.map -o $@ $< $(VTS70_LIB)

build/test/cswstest: test/cswtest.c test/cswcout.s $(VTS70_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) $(S70_LINK) -O -I include -DS70 -m $@.map -o $@ test/cswtest.c test/cswcout.s $(VTS70_LIB)

build/test/reflows70: test/reflowtest.c $(VTS70_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) $(S70_LINK) -O -I include -DS70 -m $@.map -o $@ $< $(VTS70_LIB)

build/test/timertest: test/timertest.c test/timerzp.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/timertest.c test/timerzp.s $(DOS33_LIB)

# The IP65 timer driver with IP65 and the Uthernet II: linked ahead of
# IP65's libraries, so it replaces IP65's own timer_read
build/test/nettest: test/nettest.c $(IP65_OBJ) $(DOS33_LIB) $(IP65_LIBS)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -I $(IP65)/inc -m $@.map -o $@ test/nettest.c $(IP65_OBJ) $(IP65_LIBS) $(DOS33_LIB)

# Regression tests that run in cc65's 6502 simulator, sim65, without an
# Apple II: the timer modules, the window's gauge, the reflow filter and
# Soft-70's drawing, built for sim6502.
SIM_DIR  := build/sim
SIM_MODS := timer tick kbhit gettime settime
SIM_REFLOW := $(SIM_DIR)/reflow.o
SIM_OBJ  := $(patsubst %,$(SIM_DIR)/%.o,$(SIM_MODS))
SIM65    ?= sim65

$(SIM_DIR)/%.o: libsrc/dos33/%.s libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 -I libsrc/dos33 -o $@ $<

$(SIM_DIR)/win/%.o: libsrc/win/%.s $(WIN_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 $(WIN_FLAGS) -o $@ $<

$(SIM_DIR)/win/%.o: libsrc/s80/%.s $(WIN_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 $(WIN_FLAGS) -o $@ $<

$(SIM_DIR)/timersim: test/sim/timersim.c test/sim/shim.s test/timerzp.s $(SIM_OBJ)
	$(CL65) -t sim6502 -O -I include -o $@ $^

$(SIM_DIR)/gaugesim: test/sim/gaugesim.c test/sim/shim.s test/sim/winshim.s test/sim/bssfill.s $(SIM_DIR)/win/s80.o $(SIM_DIR)/win/win.o $(SIM_OBJ)
	$(CL65) -t sim6502 -C test/sim/sim0c00.cfg -O -I include -o $@ $^

S70_SIM_MODS := s80 cputc cpeekc gotoxy gotoy wherex wherey clrscr s70 font
S70_SIM_OBJ  := $(patsubst %,$(SIM_DIR)/s70/%.o,$(S70_SIM_MODS))

$(SIM_DIR)/s70/%.o: libsrc/s70/%.s $(S70_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 $(S70_FLAGS) -o $@ $<

$(SIM_DIR)/s70/%.o: libsrc/s80/%.s $(S70_INC) $(VT_INC) libsrc/dos33/timer.inc
	@mkdir -p $(@D)
	$(CA65) -t sim6502 $(S70_FLAGS) -o $@ $<

$(SIM_DIR)/s70sim: test/sim/s70sim.c test/sim/shim.s test/sim/winshim.s test/sim/s70shim.s $(S70_SIM_OBJ) $(SIM_OBJ)
	$(CL65) -t sim6502 -C test/sim/sim4000.cfg -O -I include -o $@ $^

$(SIM_DIR)/reflowsim: test/sim/reflowsim.c test/sim/reflowshim.s $(SIM_REFLOW)
	$(CL65) -t sim6502 -O -I include -o $@ $^

# Link-time guards (DESIGN.md 4.2): a call to each guarded function must
# fail to link, naming its guard symbol, while a control program links
linktest: $(DOS33_LIB)
	CL65=$(CL65) bash test/linktest.sh $(DOS33_LIB)

simtest: $(SIM_DIR)/timersim $(SIM_DIR)/gaugesim $(SIM_DIR)/reflowsim $(SIM_DIR)/s70sim
	$(SIM65) $(SIM_DIR)/timersim
	$(SIM65) $(SIM_DIR)/gaugesim
	$(SIM65) $(SIM_DIR)/reflowsim
	$(SIM65) $(SIM_DIR)/s70sim

clean:
	rm -rf build lib

# Probes for exec() under DOS 3.3 (DESIGN.md 5.10): DOS commands through
# COUT and page 2 across BLOAD; a DOS error after the hand-off, with and
# without the stub's reset
build/test/bloadprobe: test/bloadprobe.c test/cswcout.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/bloadprobe.c test/cswcout.s $(DOS33_LIB)

build/test/errprobe: test/errprobe.c test/errstub.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/errprobe.c test/errstub.s $(DOS33_LIB)

build/test/errproberaw: test/errprobe.c test/errstub.s $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DRAW -m $@.map -o $@ test/errprobe.c test/errstub.s $(DOS33_LIB)

# exec() under DOS 3.3 (DESIGN.md 5.10): exectest execs argtest with
# arguments (also with the VideoTerm backend); execatest execs an
# Applesoft program
build/test/exectest: test/exectest.c $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(DOS33_LIB)

build/test/exectestvt: test/exectest.c $(VT_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(VT_LIB)

build/test/execatest: test/exectest.c $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DEXECA -m $@.map -o $@ $< $(DOS33_LIB)

build/test/argtest: test/argtest.c $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(DOS33_LIB)
