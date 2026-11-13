# a2lib

A C library for the Apple II+, built on [cc65](https://github.com/cc65/cc65)'s
`apple2` target. It fills the gaps that keep cc65 programs from being
full-featured on a stock II+:

- **DOS 3.3 file I/O.** Stock cc65 supports file I/O only under ProDOS;
  under DOS 3.3, `open` fails with `ENOSYS`. a2lib implements cc65's POSIX
  layer on top of the DOS 3.3 File Manager, so `open`, `read`, `write` and
  stdio work under both DOSes with the same behavior.
- **Display backends**, selected at link time. Conio and console output
  use a Videx VideoTerm in slot 3 when present. Without one, a program
  falls back to either the stock 40-column screen or a 40-column window
  onto an 80 × 24 screen, which follows the cursor or pans under program
  control. An optional hi-res "Soft-70" display is planned.
- **Cooperative timer and software clock.** A stock II+ has no timer, so
  a2lib counts time while programs wait in the library (for keys,
  network packets, or explicitly), and runs timer callbacks then:
  one-shot or periodic, for regular "go" intervals and timeouts. Under
  DOS 3.3, `time()` and `clock_gettime` return the up-time until a
  program sets the clock, for example from an Internet time server, and
  IP65 programs can use it as their timer (`include/a2timer.h`).
- **DOS 3.3 interrupts.** Stock cc65 can only install interrupt
  handlers under ProDOS. a2lib installs them under DOS 3.3 too, keeping
  the Language Card banking intact across interrupts.

The first programs built on it are a telnet terminal and a Gopher client
for the Uthernet II.

## Status

- **Increment 1** of the DOS 3.3 file layer passes all its tests under
  DOS 3.3: `open`, `close`, `read` and `write`, including `O_APPEND`,
  `O_TRUNC` and `O_EXCL`, for T, B, A and I files, plus stdio on top.
- **Increment 2** adds `lseek`, `remove`, `rename` and `stat`, and also
  passes all its tests under DOS 3.3.
- **Increment 3** adds directories (`opendir`, `readdir`, `closedir`,
  `rewinddir`) over the DOS 3.3 catalog, and `st_blocks` in `stat`, and
  also passes all its tests under DOS 3.3.
- **Increment 4** adds interrupt support under DOS 3.3 (cc65's
  interruptors, as used by the mouse and serial drivers), and also passes
  all its tests under DOS 3.3. The interrupt paths are tested with
  simulated interrupts until ReplicApple2Plus has a card that raises IRQ.
- **Increment 5** adds the VideoTerm backend (`lib/apple2-dos33-vt.lib`),
  and passes all its tests both with the card and on the 40-column
  fallback.
- **Increment 6** adds the 40-column window (`lib/apple2-dos33-vtwin.lib`),
  and passes all its tests, with and without the card.
- **Increment 7** adds the cooperative timer, the software clock, the
  40-column window's position gauge, and an IP65 timer driver. It passes
  all its tests under DOS 3.3 and the sim65 regression tests
  (`make simtest`).

Next: the reflow filter and Soft-70.

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

`lib/apple2-dos33.lib` is a complete replacement for cc65's `apple2.lib`,
built from the installed cc65's library with the DOS 3.3 modules swapped
in. Build with:

```sh
cl65 -t apple2 -I include -o prog prog.c lib/apple2-dos33.lib
```

`-I include` selects a2lib's DOS 3.3 `dirent.h`, which programs that use
the directory functions need. To use a Videx VideoTerm in slot 3 when one
is present, link one of these instead:

| Library | Without a VideoTerm |
|---|---|
| `lib/apple2-dos33-vt.lib` | The stock 40-column screen |
| `lib/apple2-dos33-vtwin.lib` | A 40-column window onto an 80 × 24 screen; see `include/c40win.h` | Compiling with it but linking without the
library fails at link time, so the two can't be mixed up silently.

Rebuild a2lib after updating cc65, so the stock modules it contains match
your toolchain.

Programs run on a 48K II+ under stock DOS 3.3 (ProDOS builds need 64K).
Behavior matches cc65 under ProDOS wherever DOS 3.3 can represent it, and
fails visibly where it can't:

| Topic | Behavior |
|---|---|
| File names | `"NAME"` uses the last-used slot and drive; `"NAME,S6,D2,V254"` selects them, as at the DOS prompt. Names are case-insensitive. |
| New files | Type from `_filetype` (default binary, as in cc65): `PRODOS_T_TXT` → T, `PRODOS_T_BIN` → B, `PRODOS_T_BAS` → A, `PRODOS_T_INT` → I. |
| T files | Stored as DOS 3.3 text (high bit set, CR line endings) and read back byte-for-byte as written. Bytes `$80`–`$FF` are rejected with `EINVAL`; use B files for 8-bit data. |
| B files | The 4-byte address/length header is hidden. `_auxtype` sets the load address; the length is exact. Files still `BLOAD` and `BRUN`. |
| Seeking | As under ProDOS, except that T files can be positioned past their end, to reach records of random-access files. Positions are limited to 16 bits. |
| Rename | The new name takes no suffixes, and an existing new name fails with `EEXIST`, as under ProDOS. |
| Directories | `opendir` takes a location, not a path: `""` or `"."` for the default drive, optionally with suffixes (`",D2"`). `struct dirent` has the name, ProDOS-equivalent type, access and size in blocks and sectors; it omits the byte size, dates and aux type, which the catalog doesn't record (use `stat`). |
| Clock | `time()` and `clock_gettime` count the up-time until `clock_settime` sets the clock; `a2_clock_age` tells whether, and how long ago, it was set. |
| Errors | Reported with the same `errno` and `_oserror` values as under ProDOS. |

## Using the timer with IP65

Link `lib/a2lib-ip65.o` before IP65's libraries. It replaces IP65's
Apple II timer driver, which busy-waits about 33 ms on every
`timer_read`, with one that waits a single tick (about 3.9 ms) and
reports counted milliseconds:

```sh
cl65 -t apple2 -I include -o prog prog.c lib/a2lib-ip65.o ip65.lib a2uther2.lib lib/apple2-dos33.lib
```

## Testing

`test/filetest.c` checks every file-layer behavior above and prints a
`PASS` or `FAIL` line for each. Run it from a DOS 3.3 disk with a writable
disk in the default drive. `test/vttest.c` checks the display backends,
and `test/timertest.c` the timer and clock. The target test environment
is the [ReplicApple2Plus](https://github.com/sbabcoc/ReplicApple2Plus)
emulator.

`make simtest` runs regression tests for the timer and the window's
gauge in cc65's 6502 simulator, `sim65`, with no Apple II needed.

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
