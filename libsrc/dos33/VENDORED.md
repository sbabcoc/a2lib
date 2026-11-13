# Vendored cc65 files

`filedes.inc` and `mli.inc` are unmodified copies from cc65's
`libsrc/apple2/` (commit `eebf54a`), distributed under the zlib license.
The DOS 3.3 modules share the stock runtime's file descriptor table and
MLI parameter block (`mliparam`, used by `rwepilog`), so their layouts
must match the cc65 version the library is linked with. These layouts
have not changed since 2005.

Modified copies of cc65 modules, each with a note in its header
explaining the change:

- `write.s` (from `libsrc/apple2/write.s`): the `O_APPEND` path calls
  `seekend` instead of ProDOS MLI calls.
- `crt0.s` (from `libsrc/apple2/crt0.s`): under DOS 3.3, patches the 6502
  vectors in Language Card RAM before the module constructors run.
- `irq.s` (from `libsrc/apple2/irq.s`): the stock ProDOS path is kept;
  a DOS 3.3 path is added.

Because these replace stock modules in `lib/apple2-dos33.lib`, compare
them with cc65's versions after updating cc65.
