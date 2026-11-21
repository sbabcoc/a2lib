#!/usr/bin/env python3
#
# Selector check for the add-on libraries (DESIGN.md 2), run by
# test/linktest.sh:
#
#   python3 test/selcheck.py LIBDIR
#
# A program lists the add-ons' selectors, then the add-ons in the order
# below, then the core. ld65 scans each library once, so a module of an
# add-on that replaces a module of a library listed after it must be pulled
# in by the add-on's selector whenever a module of those later libraries
# may import it; otherwise a program reaching it only through such a module
# (cputs -> cputc) would get the later library's. For each add-on, this
# checks:
#
#   - the modules its selector pulls in are exactly those modules: one
#     missing is a silent fallback to the later library's; one more costs
#     every program its size;
#   - each name its selector imports is defined in the add-on;
#   - parity: where one of its modules replaces a later one, every symbol
#     of the later module that some module imports is defined by the
#     replacement too, so the later module can't be linked beside it.
#
# A module identical to the later library's (tick.o, kbhit.o and timer.o,
# bundled into the display libraries) isn't a replacement.
#
# OD65 and AR65 name od65 and ar65, if not on PATH.

import hashlib
import os
import re
import subprocess
import sys
import tempfile

OD65 = os.environ.get("OD65", "od65")
AR65 = os.environ.get("AR65", "ar65")

# Each add-on, with the libraries listed after it on a link line
ORDER = {
    "vt":     ["reflow", "timer", "dos33"],
    "c40win": ["reflow", "timer", "dos33"],
    "soft70": ["reflow", "timer", "dos33"],
    "reflow": ["timer", "dos33"],
    "timer":  ["dos33"],
}


def names(path, what):
    out = subprocess.run([OD65, "--dump-" + what, path], check=True,
                         capture_output=True, text=True).stdout
    return set(re.findall(r'Name:\s+"([^"]*)"', out))


def modules(lib, tmp):
    """{module name: (exports, imports, digest)} for a library"""
    d = os.path.join(tmp, os.path.basename(lib))
    os.mkdir(d)
    members = subprocess.run([AR65, "t", os.path.abspath(lib)], check=True,
                             capture_output=True, text=True).stdout.split()
    subprocess.run([AR65, "x", os.path.abspath(lib)] + members, check=True,
                   cwd=d)
    mods = {}
    for m in members:
        p = os.path.join(d, m)
        with open(p, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        mods[m] = (names(p, "exports"), names(p, "imports"), digest)
    return mods


def main(libdir):
    fail = False
    with tempfile.TemporaryDirectory() as tmp:
        libs = {n: modules(os.path.join(libdir, "a2lib-%s.lib" % n), tmp)
                for n in set(ORDER) | {"dos33"}}
        for addon, later in ORDER.items():
            own = libs[addon]
            rest = [(n, m, v) for n in later for m, v in libs[n].items()]
            imported = set().union(*(v[1] for _, _, v in rest))
            allimp = imported | set().union(*(v[1] for v in own.values()))
            need = set()
            for m, (exp, _, digest) in own.items():
                for n, m2, (exp2, _, digest2) in rest:
                    shared = exp & exp2
                    if not shared or digest == digest2:
                        continue
                    if shared & imported:
                        need.add(m)
                    for s in sorted((exp2 - exp) & allimp):
                        print("FAIL  %s: %s replaces %s's %s but not its %s"
                              % (addon, m, n, m2, s))
                        fail = True
            sel = names(os.path.join(libdir, "a2lib-%s.o" % addon), "imports")
            have = set().union(*(v[0] for v in own.values()))
            for s in sorted(sel - have):
                print("FAIL  %s: selector imports %s, which a2lib-%s.lib "
                      "doesn't define" % (addon, s, addon))
                fail = True
            got = {m for m, v in own.items() if v[0] & sel}
            for m in sorted(need - got):
                print("FAIL  %s: selector doesn't pull in %s" % (addon, m))
                fail = True
            for m in sorted(got - need):
                print("FAIL  %s: selector pulls in %s, which nothing "
                      "later imports" % (addon, m))
                fail = True
            if need == got:
                print("ok    selector %s: %s"
                      % (addon, " ".join(sorted(got))))
    return 1 if fail else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: selcheck.py LIBDIR")
    sys.exit(main(sys.argv[1]))
