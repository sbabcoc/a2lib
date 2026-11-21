#!/usr/bin/env python3
#
# Selector check for the add-on libraries (DESIGN.md 2), run by
# test/linktest.sh:
#
#   python3 test/selcheck.py LIBDIR
#
# A program lists the add-ons' selectors, then the add-ons in the order
# below, then the core. ld65 scans each library once, so a module of an
# add-on that takes the place of a module in a library listed after it (a
# replacement, or a copy of a core module, tools/stockcopy.py) is linked
# only if a reference to it is open when ld65 scans the add-on. A module
# of those later libraries importing it, and not itself replaced or copied,
# would get the later library's instead: such a module must be pulled in by
# the add-on's selector. For each add-on, this checks:
#
#   - the modules its selector pulls in are exactly those modules: one
#     missing is a silent fallback to the later library's; one more costs
#     every program its size;
#   - each name its selector imports is defined in the add-on;
#   - parity: where one of its modules takes the place of a later one,
#     every symbol of the later module that some module imports is defined
#     by the add-on's too, so the later module can't be linked beside it.
#
# A module identical to one of a later add-on (tick.o, kbhit.o and timer.o,
# bundled into the display libraries) takes nobody's place.
#
# OD65 and AR65 name od65 and ar65, if not on PATH.

import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "tools"))
import libobj  # noqa: E402

# Each add-on, with the libraries listed after it on a link line
ORDER = {
    "vt":     ["reflow", "timer", "dos33"],
    "c40win": ["reflow", "timer", "dos33"],
    "soft70": ["reflow", "timer", "dos33"],
    "reflow": ["timer", "dos33"],
    "timer":  ["dos33"],
}


def check(addon, own, later, selector):
    """Prints and returns the failures for one add-on"""
    fail = []
    bundled = {m.digest for m in own.values()} & {
        m2.digest for n, lib in later if n != "dos33" for m2 in lib.values()}
    rest = [m2 for _, lib in later for m2 in lib.values()]
    # Pairs (add-on module, later module it takes the place of)
    pairs = [(m, m2) for m in own.values() if m.digest not in bundled
             for m2 in libobj.shadows(m, rest)]
    taken = {id(m2) for m, m2 in pairs} | {id(m2) for m2 in rest
                                          if m2.digest in bundled}
    callers = [m2 for m2 in rest if id(m2) not in taken]
    imported = set().union(*(m.imports for m in list(own.values()) + rest))
    need = set()
    for m, m2 in pairs:
        if any(c.imports & m.exports & m2.exports for c in callers):
            need.add(m.name)
        for s in sorted((m2.exports - m.exports) & imported):
            fail.append("%s takes the place of %s but doesn't define %s"
                        % (m.name, m2.name, s))
    sel = libobj.names(selector, "imports")
    have = set().union(*(m.exports for m in own.values()))
    for s in sorted(sel - have):
        fail.append("selector imports %s, which a2lib-%s.lib doesn't "
                    "define" % (s, addon))
    got = libobj.forced(own, selector)
    for m in sorted(need - got):
        fail.append("selector doesn't pull in %s" % m)
    for m in sorted(got - need):
        fail.append("selector pulls in %s, which no later module needs" % m)
    for f in fail:
        print("FAIL  %s: %s" % (addon, f))
    if not fail:
        print("ok    selector %s: %s"
              % (addon, " ".join(sorted(got)) or "nothing"))
    return fail


def main(libdir):
    fail = False
    with tempfile.TemporaryDirectory() as tmp:
        libs = {n: libobj.library(os.path.join(libdir, "a2lib-%s.lib" % n),
                                  tmp)
                for n in set(ORDER) | {"dos33"}}
        for addon, later in ORDER.items():
            selector = os.path.join(libdir, "a2lib-%s.o" % addon)
            if check(addon, libs[addon], [(n, libs[n]) for n in later],
                     selector):
                fail = True
    return 1 if fail else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: selcheck.py LIBDIR")
    sys.exit(main(sys.argv[1]))
