# Vendored cc65 files

`filedes.inc` and `mli.inc` are unmodified copies from cc65's
`libsrc/apple2/` (commit `eebf54a`), distributed under the zlib license.
The DOS 3.3 modules share the stock runtime's file descriptor table and
MLI parameter block (`mliparam`, used by `rwepilog`), so their layouts
must match the cc65 version the library is linked with. These layouts
have not changed since 2005.

`write.s` is a modified copy of cc65's `libsrc/apple2/write.s`; see the
note in its header.
