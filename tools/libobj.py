#
# Reading cc65 object files and libraries with od65 and ar65, for
# tools/stockcopy.py and test/selcheck.py. OD65 and AR65 name od65 and
# ar65, if not on PATH.
#

import hashlib
import os
import re
import subprocess

OD65 = os.environ.get("OD65", "od65")
AR65 = os.environ.get("AR65", "ar65")


class Module:
    """One object file: its name, exported and imported symbols, and a
    digest of its contents (equal digests: the same module)"""

    def __init__(self, name, path):
        self.name = name
        self.path = path
        self.exports = names(path, "exports")
        self.imports = names(path, "imports")
        with open(path, "rb") as f:
            self.digest = hashlib.sha256(f.read()).hexdigest()


def names(path, what):
    """The symbols an object file exports or imports (what: "exports" or
    "imports")"""
    out = subprocess.run([OD65, "--dump-" + what, path], check=True,
                         capture_output=True, text=True).stdout
    return set(re.findall(r'Name:\s+"([^"]*)"', out))


def library(lib, tmp):
    """{module name: Module} for a library, extracted into a new folder
    under tmp"""
    lib = os.path.abspath(lib)
    d = os.path.join(tmp, os.path.basename(lib))
    os.mkdir(d)
    members = subprocess.run([AR65, "t", lib], check=True,
                             capture_output=True, text=True).stdout.split()
    subprocess.run([AR65, "x", lib] + members, check=True, cwd=d)
    return {m: Module(m, os.path.join(d, m)) for m in members}


def forced(lib, selector):
    """The modules of lib that the selector object pulls in"""
    want = names(selector, "imports")
    return {m for m, mod in lib.items() if mod.exports & want}


def shadows(mod, others):
    """The modules of others that mod takes the place of: those sharing an
    exported symbol with it"""
    return [o for o in others if o.exports & mod.exports]
