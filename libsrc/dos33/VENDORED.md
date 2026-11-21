# Vendored cc65 files

`filedes.inc` and `mli.inc` are unmodified copies from cc65's
`libsrc/apple2/` (commit `eebf54a`), distributed under the zlib license.
The DOS 3.3 modules share the stock runtime's file descriptor table, so
its layout must match the cc65 version the library is linked with; it
has not changed since 2005. `mli.inc` supplies `READ_CALL` and
`WRITE_CALL`, the operation codes stock `read.s` passes to `rwcommon`.

Modified copies of cc65 modules, each with a note in its header
explaining the change. a2lib runs under DOS 3.3 only, so their ProDOS
paths are removed (DESIGN.md 10.22); the code DOS 3.3 shares is stock's:

- `write.s` (from `libsrc/apple2/write.s`): no `O_APPEND` path (`rwfile.s`
  moves to the end of the file); the device path's count goes to
  `rw_count`, not ProDOS's parameter block. Its loop also has a fix stock
  doesn't (yet): a count that is a nonzero multiple of 256 wrote 256
  characters too many (DESIGN.md 10.28). Drop it once cc65's
  `write.s` has the same fix.
- `crt0.s` (from `libsrc/apple2/crt0.s`): patches the 6502 vectors in
  Language Card RAM before the module constructors run, not after.
- `mainargs.s` (from `libsrc/apple2/mainargs.s`): argv[0] is `""`; takes
  the arguments `exec()` leaves after its command in page 2 (DESIGN.md
  5.10), and includes `machine.inc` for that code's characters.
- `oserror.s` (from `libsrc/apple2/oserror.s`): the stock search, with a
  table for DOS 3.3's error numbers and the library's codes (DESIGN.md
  5.6) in place of ProDOS's.
- `oserrlist.s` (from `libsrc/apple2/oserrlist.s`): the stock macros, with
  DOS 3.3's messages in place of ProDOS's.

`exec.s` replaces `libsrc/apple2/exec.s` but isn't a copy of it: it keeps
the stock module's structure (its command-line copy and shutdown) with a
DOS 3.3 command in place of the ProDOS loader. `irq.s` and `initcwd.s`
replace stock modules of the same name with DOS 3.3 code of a2lib's own
(DESIGN.md 6, 5.5).

The add-on libraries' modified copies are listed beside them, in
`libsrc/timer/VENDORED.md` and `libsrc/reflow/VENDORED.md`.

Because these replace stock modules in `lib/a2lib-dos33.lib`, compare
them with cc65's versions after updating cc65.
