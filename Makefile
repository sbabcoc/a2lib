# Apple II+ C library for cc65
#
#   make            build lib/apple2-dos33.lib
#   make test       also build the test programs
#
# Link a program for DOS 3.3 by listing the library before cc65's own:
#   cl65 -t apple2 -o prog prog.c lib/apple2-dos33.lib

CA65   ?= ca65
AR65   ?= ar65
CL65   ?= cl65
TARGET := apple2

DOS33_SRC := $(wildcard libsrc/dos33/*.s)
DOS33_OBJ := $(patsubst libsrc/dos33/%.s,build/dos33/%.o,$(DOS33_SRC))
DOS33_INC := $(wildcard libsrc/dos33/*.inc)
DOS33_LIB := lib/apple2-dos33.lib

.PHONY: all test clean

all: $(DOS33_LIB)

build/dos33/%.o: libsrc/dos33/%.s $(DOS33_INC)
	@mkdir -p $(@D)
	$(CA65) -t $(TARGET) -I libsrc/dos33 -o $@ $<

$(DOS33_LIB): $(DOS33_OBJ)
	@mkdir -p $(@D)
	rm -f $@
	$(AR65) a $@ $^

test: build/test/filetest

build/test/filetest: test/filetest.c $(DOS33_LIB)
	@mkdir -p $(@D)
	$(CL65) -t $(TARGET) -O -m $@.map -o $@ $< $(DOS33_LIB)

clean:
	rm -rf build lib
