# Apple II+ C library for cc65
#
#   make            build the libraries (below)
#   make test       also build the test programs
#   make simtest    build and run the sim65 tests (no Apple II needed)
#   make linktest   check the link-time guards and the add-ons' selectors
#   make emutest    run the test programs on ReplicApple2Plus (below)
#   make screenshots  the README's screenshot, from an emutest run
#   make tags       the symbol index for editors (below); make does it too
#   make clean      remove build/ and lib/
#
# lib/a2lib-dos33.lib, the core, is a complete replacement for cc65's
# apple2.lib: a copy of the installed one with the DOS 3.3 modules in
# place of the stock modules of the same name, and link-time guards for
# functions with no DOS 3.3 version. Build a program for DOS 3.3 with:
#   cl65 -t apple2 -I include -o prog prog.c lib/a2lib-dos33.lib
# (-I include selects the DOS 3.3 dirent.h; it's needed only for
# directory functions.)
#
# What stock cc65 doesn't have comes in add-on libraries (DESIGN.md 2),
# each with a selector object to link ahead of it. List the selectors
# first, then the add-ons, then the core:
#   a2lib-timer     cooperative timer and software clock (a2timer.h, time.h)
#   a2lib-reflow    word-wrapping stdio console output (a2reflow.h)
#   a2lib-vt        the Videx VideoTerm, or the stock 40-column screen
#   a2lib-soft70    the VideoTerm, or Soft-70: 70 of 80 columns in hi-res
#                   (soft70.h); link with --start-addr 0x4000
# For example:
#   cl65 -t apple2 -I include -o prog prog.c lib/a2lib-vt.o lib/a2lib-timer.o \
#       lib/a2lib-vt.lib lib/a2lib-timer.lib lib/a2lib-dos33.lib
# The display libraries carry the timer's kbhit, and the Soft-70 library the
# timer, which its gauge and cursor use.
#
# ld65 scans each library once, in order, and takes only modules that
# resolve references open at that point. Hence a complete core (a stock
# module reached through another, fopen -> open, would otherwise come from
# apple2.lib), the copies of stock modules in the add-ons (cputs -> cputc
# would otherwise get stock cputc), and the selectors (printf -> write ->
# COUT, for which all of stdio would need copying). Rebuild after updating
# cc65, so the stock modules match the toolchain.

CA65   ?= ca65
AR65   ?= ar65
CL65   ?= cl65
OD65   ?= od65
PYTHON ?= python3
TARGET := apple2
export AR65 OD65

# Directory holding the installed cc65 libraries
CC65_LIB  ?= $(shell $(CL65) --print-target-path)/../lib
STOCK_LIB := $(CC65_LIB)/$(TARGET).lib

# The symbol index (tags), for an editor's go-to-definition: a2lib's
# sources and the cc65 sources it builds on, read with tools/ca65.ctags.
# It needs Universal Ctags (https://ctags.io); macOS's own ctags can't
# read that definition, so a Homebrew one is looked for too. Without
# either, make leaves the index out. CC65_SRC is a cc65 checkout; an
# installed cc65 has no library sources, and then only a2lib's are
# indexed.
CTAGS    ?= $(shell for c in ctags "$$(brew --prefix universal-ctags 2>/dev/null)/bin/ctags"; do \
              "$$c" --version 2>/dev/null | grep -q 'Universal Ctags' && { echo "$$c"; break; }; done)
CC65_SRC ?= $(CC65_LIB)/..
TAGS_CC65 := $(abspath $(wildcard $(addprefix $(CC65_SRC)/,libsrc/apple2 libsrc/common libsrc/runtime asminc include)))
TAGS_SRC  := $(wildcard libsrc/*/*.s libsrc/*/*.inc include/*.h test/*.c test/*.s test/*/*.s test/*/*.c)

DOS33_SRC := $(wildcard libsrc/dos33/*.s)
DOS33_OBJ := $(patsubst libsrc/dos33/%.s,build/dos33/%.o,$(DOS33_SRC))
DOS33_INC := $(wildcard libsrc/dos33/*.inc)
DOS33_LIB := lib/a2lib-dos33.lib

# Link-time guards (DESIGN.md 4.2): each replaces the stock ProDOS module
# of the same name, so a call to a function with no DOS 3.3 implementation
# (or without the add-on that has it) fails to link instead of at run time
GUARD_SRC := $(wildcard libsrc/guard/*.s)
GUARD_OBJ := $(patsubst libsrc/guard/%.s,build/guard/%.o,$(GUARD_SRC))

TIMER_SRC := $(wildcard libsrc/timer/*.s)
TIMER_OBJ := $(patsubst libsrc/timer/%.s,build/timer/%.o,$(TIMER_SRC))
TIMER_INC := libsrc/timer/timer.inc
TIMER_LIB := lib/a2lib-timer.lib

REFLOW_SRC := $(wildcard libsrc/reflow/*.s)
REFLOW_OBJ := $(patsubst libsrc/reflow/%.s,build/reflow/%.o,$(REFLOW_SRC))
REFLOW_LIB := lib/a2lib-reflow.lib

VT_SRC := $(wildcard libsrc/vt/*.s)
VT_OBJ := $(patsubst libsrc/vt/%.s,build/vt/%.o,$(VT_SRC))
VT_INC := $(wildcard libsrc/vt/*.inc)
VT_LIB := lib/a2lib-vt.lib

# The 80 x 24 model (libsrc/s80), assembled with the display.inc of the
# backend that shows it, Soft-70's (libsrc/s70)
S80_SRC := $(wildcard libsrc/s80/*.s)
S80_INC := $(wildcard libsrc/s80/*.inc)

.PHONY: emutest screenshots all test simtest linktest clean

S70_SRC := $(wildcard libsrc/s70/*.s)
S70_OBJ := $(patsubst libsrc/s70/%.s,build/s70/%.o,$(S70_SRC)) \
           $(patsubst libsrc/s80/%.s,build/s70/%.o,$(S80_SRC))
S70_INC := $(wildcard libsrc/s70/*.inc) $(S80_INC)
VTS70_LIB := lib/a2lib-soft70.lib

# The add-ons' selector objects (libsrc/select)
SELECT := $(patsubst libsrc/select/%.s,lib/a2lib-%.o,$(wildcard libsrc/select/*.s))

IP65_OBJ := lib/a2lib-ip65.o

# An IP65 checkout (https://github.com/cc65/ip65), for the network test,
# with its TCP library and Uthernet II driver built (make -C ip65
# ip65_tcp.lib; make -C drivers a2uther2.lib). Without IP65=, make test
# leaves the network test out.
IP65 ?=
IP65_LIBS = $(IP65)/ip65/ip65_tcp.lib $(IP65)/drivers/a2uther2.lib
NET_TEST := $(if $(IP65),build/test/nettest)

all: $(DOS33_LIB) $(TIMER_LIB) $(REFLOW_LIB) $(VT_LIB) $(VTS70_LIB) $(SELECT) $(IP65_OBJ) $(if $(CTAGS),tags)

# The symbol index: rebuilt when a2lib's sources change (after a cc65
# update, make -B tags)
tags: $(TAGS_SRC) tools/ca65.ctags
	@test -n "$(CTAGS)" || { echo "make tags: Universal Ctags not found (set CTAGS=)"; false; }
	$(CTAGS) --quiet --options=NONE --options=tools/ca65.ctags -R -f $@ \
	  $(abspath libsrc include test) $(TAGS_CC65)

# The core: stock apple2.lib with the DOS 3.3 modules and the guards
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

# Each add-on also gets copies of the core's modules that call into it
# (tools/stockcopy.py; DESIGN.md 2), so it needs the core and its selector
STOCKCOPY := tools/stockcopy.py tools/libobj.py $(DOS33_LIB)

# Selectors: one object per add-on, linked ahead of it
lib/a2lib-%.o: libsrc/select/%.s
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -o $@ $<

# Cooperative timer and software clock
build/timer/%.o: libsrc/timer/%.s $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/timer -I libsrc/dos33 -o $@ $<

$(TIMER_LIB): $(TIMER_OBJ) lib/a2lib-timer.o $(STOCKCOPY)
	@mkdir -p $(@D)
	rm -f $@
	$(AR65) r $@ $(TIMER_OBJ)
	$(PYTHON) tools/stockcopy.py $@ $(DOS33_LIB) lib/a2lib-timer.o

# Reflow filter, with the vectored COUT and the stock screen's width
build/reflow/%.o: libsrc/reflow/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

$(REFLOW_LIB): $(REFLOW_OBJ) lib/a2lib-reflow.o $(STOCKCOPY)
	@mkdir -p $(@D)
	rm -f $@
	$(AR65) r $@ $(REFLOW_OBJ)
	$(PYTHON) tools/stockcopy.py $@ $(DOS33_LIB) lib/a2lib-reflow.o

# VideoTerm backend: VideoTerm-aware conio modules, and the timer's tick
# hook and kbhit (their cgetc ticks too)
build/vt/%.o: libsrc/vt/%.s $(VT_INC) $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/vt -I libsrc/timer -I libsrc/dos33 -o $@ $<

$(VT_LIB): $(VT_OBJ) build/timer/tick.o build/timer/kbhit.o lib/a2lib-vt.o $(STOCKCOPY)
	@mkdir -p $(@D)
	rm -f $@
	$(AR65) r $@ $(VT_OBJ) build/timer/tick.o build/timer/kbhit.o
	$(PYTHON) tools/stockcopy.py $@ $(DOS33_LIB) lib/a2lib-vt.o

# IP65 timer driver on the cooperative timer: an object file, listed on the
# link line before IP65's library (libsrc/ip65/a2timer.s)
$(IP65_OBJ): libsrc/ip65/a2timer.s $(TIMER_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/timer -o $@ $<

# Soft-70 with the VideoTerm: vt.s and Soft-70's modules, on the shared
# 80 x 24 model, and the timer its gauge and cursor use. Programs are
# linked with --start-addr 0x4000.
S70_FLAGS := -I libsrc/s70 -I libsrc/s80 -I libsrc/vt -I libsrc/timer -I libsrc/dos33

build/s70/%.o: libsrc/s70/%.s $(S70_INC) $(VT_INC) $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) $(S70_FLAGS) -o $@ $<

build/s70/%.o: libsrc/s80/%.s $(S70_INC) $(VT_INC) $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) $(S70_FLAGS) -o $@ $<

# The default font, generated from its source (tools/s70font.txt)
libsrc/s70/font.s: tools/s70font.txt tools/s70font.py
	python3 tools/s70font.py $< $@

$(VTS70_LIB): $(S70_OBJ) build/vt/vt.o build/timer/tick.o build/timer/kbhit.o build/timer/timer.o lib/a2lib-soft70.o $(STOCKCOPY)
	@mkdir -p $(@D)
	rm -f $@
	$(AR65) r $@ build/vt/vt.o $(S70_OBJ) build/timer/tick.o build/timer/kbhit.o build/timer/timer.o
	$(PYTHON) tools/stockcopy.py $@ $(DOS33_LIB) lib/a2lib-soft70.o

# What a test program links: its add-ons' selectors, the add-ons, the core
L_CORE   := $(DOS33_LIB)
L_TIMER  := lib/a2lib-timer.o $(TIMER_LIB) $(DOS33_LIB)
L_REFLOW := lib/a2lib-reflow.o $(REFLOW_LIB) $(DOS33_LIB)
L_VT     := lib/a2lib-vt.o $(VT_LIB) $(DOS33_LIB)
L_S70    := lib/a2lib-soft70.o $(VTS70_LIB) $(DOS33_LIB)

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

test: build/test/filetest build/test/vttest build/test/timertest build/test/cswtest \
      build/test/reflowtest build/test/reflowvt \
      build/test/s70test build/test/cswstest build/test/reflows70 $(NET_TEST) \
      build/test/bloadprobe build/test/errprobe build/test/errproberaw \
      build/test/exectest build/test/exectestvt build/test/execatest build/test/argtest \
      build/test/wptest

build/test/filetest: test/filetest.c test/irqtest.s test/cswcout.s test/coutcount.s $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/filetest.c test/irqtest.s test/cswcout.s test/coutcount.s $(L_CORE)

build/test/vttest: test/vttest.c $(L_VT)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(L_VT)

build/test/cswtest: test/cswtest.c test/cswcout.s $(L_VT)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/cswtest.c test/cswcout.s $(L_VT)

build/test/reflowtest: test/reflowtest.c $(L_REFLOW)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(L_REFLOW)

build/test/reflowvt: test/reflowtest.c lib/a2lib-vt.o lib/a2lib-reflow.o $(VT_LIB) $(REFLOW_LIB) $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< lib/a2lib-vt.o lib/a2lib-reflow.o $(VT_LIB) $(REFLOW_LIB) $(DOS33_LIB)

build/test/s70test: test/vttest.c $(L_S70)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) $(S70_LINK) -O -I include -DS70 -m $@.map -o $@ $< $(L_S70)

build/test/cswstest: test/cswtest.c test/cswcout.s $(L_S70)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) $(S70_LINK) -O -I include -DS70 -m $@.map -o $@ test/cswtest.c test/cswcout.s $(L_S70)

build/test/reflows70: test/reflowtest.c lib/a2lib-soft70.o lib/a2lib-reflow.o $(VTS70_LIB) $(REFLOW_LIB) $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) $(S70_LINK) -O -I include -DS70 -m $@.map -o $@ $< lib/a2lib-soft70.o lib/a2lib-reflow.o $(VTS70_LIB) $(REFLOW_LIB) $(DOS33_LIB)

build/test/timertest: test/timertest.c test/timerzp.s $(L_TIMER)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/timertest.c test/timerzp.s $(L_TIMER)

# The IP65 timer driver with IP65 and the Uthernet II: linked ahead of
# IP65's libraries, so it replaces IP65's own timer_read
build/test/nettest: test/nettest.c $(IP65_OBJ) $(L_TIMER) $(IP65_LIBS)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -I $(IP65)/inc -m $@.map -o $@ test/nettest.c $(IP65_OBJ) $(IP65_LIBS) $(L_TIMER)

# Regression tests that run in cc65's 6502 simulator, sim65, without an
# Apple II: the timer modules, the reflow filter, and Soft-70's drawing
# with the 80 x 24 model and its gauge, built for sim6502.
SIM_DIR  := build/sim
SIM_MODS := timer tick kbhit gettime settime
SIM_REFLOW := $(SIM_DIR)/reflow.o
SIM_OBJ  := $(patsubst %,$(SIM_DIR)/%.o,$(SIM_MODS))
SIM65    ?= sim65

$(SIM_DIR)/%.o: libsrc/timer/%.s $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t sim6502 -I libsrc/timer -I libsrc/dos33 -o $@ $<

$(SIM_DIR)/%.o: libsrc/reflow/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t sim6502 -I libsrc/dos33 -o $@ $<

$(SIM_DIR)/timersim: test/sim/timersim.c test/sim/shim.s test/timerzp.s $(SIM_OBJ)
	$(CL65) -t sim6502 -O -I include -o $@ $^

S70_SIM_MODS := s80 cputc cpeekc gotoxy gotoy wherex wherey clrscr s70 font
S70_SIM_OBJ  := $(patsubst %,$(SIM_DIR)/s70/%.o,$(S70_SIM_MODS))

$(SIM_DIR)/s70/%.o: libsrc/s70/%.s $(S70_INC) $(VT_INC) $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t sim6502 $(S70_FLAGS) -o $@ $<

$(SIM_DIR)/s70/%.o: libsrc/s80/%.s $(S70_INC) $(VT_INC) $(TIMER_INC) $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t sim6502 $(S70_FLAGS) -o $@ $<

$(SIM_DIR)/s70sim: test/sim/s70sim.c test/sim/shim.s test/sim/vtshim.s test/sim/s70shim.s $(S70_SIM_OBJ) $(SIM_OBJ)
	$(CL65) -t sim6502 -C test/sim/sim4000.cfg -O -I include -o $@ $^

$(SIM_DIR)/reflowsim: test/sim/reflowsim.c test/sim/reflowshim.s $(SIM_REFLOW)
	$(CL65) -t sim6502 -O -I include -o $@ $^

# Link-time guards (DESIGN.md 4.2): a call to each guarded function must
# fail to link, naming its guard symbol, while a control program links;
# and each add-on's selector must pull in its replacements (DESIGN.md 2)
linktest: all
	CL65=$(CL65) PYTHON=$(PYTHON) bash test/linktest.sh lib

simtest: $(SIM_DIR)/timersim $(SIM_DIR)/reflowsim $(SIM_DIR)/s70sim
	$(SIM65) $(SIM_DIR)/timersim
	$(SIM65) $(SIM_DIR)/reflowsim
	$(SIM65) $(SIM_DIR)/s70sim

clean:
	rm -rf build lib

# Probes for exec() under DOS 3.3 (DESIGN.md 5.10): DOS commands through
# COUT and page 2 across BLOAD; a DOS error after the hand-off, with and
# without the stub's reset
build/test/bloadprobe: test/bloadprobe.c test/cswcout.s $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/bloadprobe.c test/cswcout.s $(L_CORE)

build/test/errprobe: test/errprobe.c test/errstub.s $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ test/errprobe.c test/errstub.s $(L_CORE)

build/test/errproberaw: test/errprobe.c test/errstub.s $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DRAW -m $@.map -o $@ test/errprobe.c test/errstub.s $(L_CORE)

# exec() under DOS 3.3 (DESIGN.md 5.10): exectest execs argtest with
# arguments (also with the VideoTerm backend); execatest execs an
# Applesoft program
build/test/exectest: test/exectest.c $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(L_CORE)

build/test/exectestvt: test/exectest.c $(L_VT)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(L_VT)

build/test/execatest: test/exectest.c $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -DEXECA -m $@.map -o $@ $< $(L_CORE)

build/test/argtest: test/argtest.c $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(L_CORE)

# A disk write-protected while a file is open (DESIGN.md 5.11): make
# emutest's script protects drive 2 mid-run
build/test/wptest: test/wptest.c $(L_CORE)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -I include -m $@.map -o $@ $< $(L_CORE)
