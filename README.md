# a2lib

A C library for the Apple II+, built on [cc65](https://github.com/cc65/cc65)'s
`apple2` target. It fills the gaps that keep cc65 programs from being
full-featured on a stock II+:

- **DOS 3.3 file I/O.** Stock cc65 supports file I/O only under ProDOS;
  under DOS 3.3, `open` fails with `ENOSYS`. a2lib implements cc65's POSIX
  layer on top of the DOS 3.3 File Manager, so `open`, `read`, `write` and
  stdio work under both DOSes with the same behavior.
- **Display backends** *(planned)*: Videx VideoTerm 80 columns, a 40-column
  window over an 80-column screen, and an optional hi-res "Soft-70"
  display, selected at link time.
- **DOS 3.3 interrupts** *(planned)*.

The first programs built on it are a telnet terminal and a Gopher client
for the Uthernet II.

## Status

Increment 1 of the DOS 3.3 file layer is complete: `open`, `close`,
`read` and `write`, including `O_APPEND`, `O_TRUNC` and `O_EXCL`, for T, B,
A and I files. It builds and links against current cc65 but **has not yet
been run on DOS 3.3**; [DESIGN.md](DESIGN.md) section 10.2 lists the
assumptions to confirm on the first run.

Next: `lseek`, `remove`, `rename`, `stat` and directories.

## Building

Requires a **current cc65 built from source**. a2lib's `write.s` is derived
from cc65's own and depends on runtime symbols added in 2024
(`uppercasemask`), which older releases such as V2.19 don't have.

```sh
git clone https://github.com/cc65/cc65
make -C cc65 -j"$(nproc)"
export PATH="$PWD/cc65/bin:$PATH"

make          # lib/apple2-dos33.lib
make test     # also build/test/filetest
```

## Using the DOS 3.3 file layer

List the library **before** cc65's own, so its modules replace the stock
ones:

```sh
cl65 -t apple2 -o prog prog.c lib/apple2-dos33.lib
```

Programs run on a 48K II+ under stock DOS 3.3 (ProDOS builds need 64K).
Behavior matches cc65 under ProDOS wherever DOS 3.3 can represent it, and
fails visibly where it can't:

| Topic | Behavior |
|---|---|
| File names | `"NAME"` uses the last-used slot and drive; `"NAME,S6,D2,V254"` selects them, as at the DOS prompt. Names are case-insensitive. |
| New files | Type from `_filetype` (default binary, as in cc65): `PRODOS_T_TXT` → T, `PRODOS_T_BIN` → B, `PRODOS_T_BAS` → A, `PRODOS_T_INT` → I. |
| T files | Stored as DOS 3.3 text (high bit set, CR line endings) and read back byte-for-byte as written. Bytes `$80`–`$FF` are rejected with `EINVAL`; use B files for 8-bit data. |
| B files | The 4-byte address/length header is hidden. `_auxtype` sets the load address; the length is exact. Files still `BLOAD` and `BRUN`. |
| Errors | Reported with the same `errno` and `_oserror` values as under ProDOS. |

## Testing

`test/filetest.c` checks every file-layer behavior above and prints a
`PASS` or `FAIL` line for each. Run it from a DOS 3.3 disk with a writable
disk in the default drive. The target test environment is the
[ReplicApple2Plus](https://github.com/sbabcoc/ReplicApple2Plus) emulator.

## Documentation

[DESIGN.md](DESIGN.md) records every design decision, the reasoning behind
it, the alternatives that were rejected, and the sources each fact was
verified against.

## Upstream

The DOS 3.3 file layer is intended for contribution to cc65 once it is
working. a2lib keeps cc65's ProDOS behavior unchanged; proposed ProDOS
changes are raised with the cc65 maintainers instead.

## License

a2lib is distributed under the [zlib license](LICENSE), the same license as
cc65, so its code can move into cc65 without relicensing. Files copied or
derived from cc65 keep their original copyright notices.

## Acknowledgments

`libsrc/dos33/filedes.inc`, `mli.inc` and `write.s` are copied or derived
from cc65 (zlib license); see
[libsrc/dos33/VENDORED.md](libsrc/dos33/VENDORED.md). File Manager details
come from *Beneath Apple DOS* by Don Worth and Pieter Lechner.
