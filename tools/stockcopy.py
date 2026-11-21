#!/usr/bin/env python3
#
# Adds to an add-on library copies of the core's modules that call into it
# (DESIGN.md 2), run by the Makefile after it builds the add-on:
#
#   python3 tools/stockcopy.py ADDON.lib CORE.lib SELECTOR.o
#
# ld65 scans each library once, so a stock module taken from the core, the
# last library on the link line, resolves its calls in the core: stock
# cputs, reached from the program, would call stock cputc, not the add-on's.
# A copy of cputs in the add-on is taken when ld65 scans the add-on, and
# its call to cputc resolves there. So the add-on gets a copy of every core
# module that imports a symbol the add-on defines in place of the core, and
# then of every core module that imports a symbol of those copies, and so
# on. The modules the selector pulls in are linked whatever the program
# calls, so their callers needn't be copied: write, which calls COUT, isn't.
#
# The copies are the core's own object files, unchanged; the core holds
# the installed cc65's, so rebuilding after updating cc65 refreshes them.
# Prints the modules copied.

import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import libobj  # noqa: E402


def copies(addon, core, selector):
    """The core modules to copy into the add-on"""
    pulled = libobj.forced(addon, selector)
    # Symbols the add-on defines in place of the core's, but only when the
    # program calls them or one of their callers is copied
    open_ = set()
    for m, mod in addon.items():
        if m not in pulled and libobj.shadows(mod, core.values()):
            open_ |= mod.exports
    # Core modules the add-on takes the place of are never linked
    taken = {o.name for mod in addon.values()
             for o in libobj.shadows(mod, core.values())}
    copy = set()
    while True:
        more = {m for m, mod in core.items()
                if m not in copy and m not in taken and mod.imports & open_}
        if not more:
            return copy
        copy |= more
        for m in more:
            open_ |= core[m].exports


def main(addon_lib, core_lib, selector):
    with tempfile.TemporaryDirectory() as tmp:
        addon = libobj.library(addon_lib, tmp)
        core = libobj.library(core_lib, tmp)
        copy = sorted(copies(addon, core, selector))
        if copy:
            subprocess.run([libobj.AR65, "a", os.path.abspath(addon_lib)]
                           + [core[m].path for m in copy], check=True)
        print("%s: copies of %s" % (addon_lib, " ".join(copy) or "none"))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: stockcopy.py ADDON.lib CORE.lib SELECTOR.o")
    sys.exit(main(*sys.argv[1:]))
