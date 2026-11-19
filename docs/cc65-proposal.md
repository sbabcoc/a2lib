# Proposal: DOS 3.3 file I/O for the apple2 target

> **Note (2026-11-19):** this is the proposal as posted on cc65/cc65#3050.
> After Oliver Schmidt's review there, a2lib no longer emulates ProDOS's
> OS-specific behavior: `_oserror` holds DOS 3.3's own error numbers
> (DESIGN.md 5.6), file types are DOS 3.3's own codes (5.4), and names are
> POSIX paths, `/6/2/NAME`, with `chdir` and `getcwd` (5.5). DESIGN.md is
> current; this text is not.


*Draft for an issue on cc65/cc65. a2lib's DESIGN.md has the full
reasoning; section numbers below refer to it.*

---

Hello,

cc65's apple2 target does file I/O through ProDOS 8 only; under DOS 3.3,
`open` and friends fail with `ENOSYS`. I've written a library, **a2lib**
(<https://github.com/sbabcoc/a2lib>, zlib license), that makes cc65's own
file layer work under stock DOS 3.3: POSIX I/O, stdio and `dirent`, on
DOS 3.3's File Manager. Programs use the standard calls and need no
source changes. Following Contributing.md, I'd like to ask whether some
or all of this is wanted in cc65, and in what form, before preparing any
pull requests.

## What it does

a2lib's `apple2-dos33.lib` is cc65's `apple2.lib` with replacement
modules (`open.s`, `rwcommon.s`, `lseek.s`, `stat.s`, `sysremove.s`,
`sysrename.s`, the `dirent` functions), plus small helpers for the File
Manager and RWTS. The stock `filedes.s`, `close.s`, `read.s` and console
paths are used unchanged; `fdtab` holds the DOS 3.3 control blocks.

The guiding rule is that a program sees the same files under DOS 3.3 as
under ProDOS, and where DOS 3.3 can't do what ProDOS does, the call fails
visibly with the ProDOS-equivalent error rather than behaving
differently. Errors are translated to ProDOS codes, so `__mappederrno`,
`_oserror` and `_stroserror` work unchanged. In particular:

- **File types:** `_filetype` takes the ProDOS codes, so source stays
  portable: TXT creates a T file, BIN a B file (the default, as now), and
  the codes for Applesoft, Integer BASIC and REL create A, I and R files.
  Other types fail with `EINVAL`. `_auxtype` sets a B file's load address.
  The address and length header of B, A and I files is handled
  internally: `read`, `write`, `lseek` and `stat` see only the data.
- **Text:** T files hold high-bit ASCII and end lines with CR, so the
  layer sets and strips bit 7 and swaps `\n` and CR on the way in and
  out, losslessly; `\0` round-trips too. A byte with bit 7 set can't be
  stored in a T file, so writing one fails with `EINVAL` rather than
  being masked; 8-bit data goes in B files.
- **Names:** `,S6,D2,V254` suffixes select slot, drive and volume, as
  DOS commands do.
- **`stat`, `remove`, `rename`:** as under ProDOS, including `EEXIST` for
  a new name in use, `EACCES` for a locked file, and `EINVAL` for an open
  file.
- **`dirent`:** reads the catalog through RWTS.
- **Errors:** anything without a DOS 3.3 counterpart (subdirectories,
  `mkdir`, DIO) still fails with `ENOSYS`.

Size: a program using `open`, `read`, `write` and `close` links about
2.2 KB of file-layer code, plus a 557-byte control block per open file,
allocated with `malloc`.

## Testing

- **Emulator:** `make emutest` runs every test program headless on the
  ReplicApple2Plus emulator (II+, Disk II, VideoTerm), booted from the DOS
  3.3 System Master, with and without the VideoTerm. Its 16 runs cover
  file I/O (68 checks, including the errors above), interrupts, the
  display and console paths, and a network run that uses IP65 over an
  emulated Uthernet II. The emulation counts cycles and the runs see only
  emulated time, so they run faster than a real machine without changing
  what the programs do; the network run is paced at the II+'s real speed,
  since its server answers in wall-clock time.
- **sim65:** regression tests run in `sim65` for the parts that don't
  need a disk.
- **Real hardware:** none yet. I'd welcome help with that.

## What I'd propose, one pull request per item

1. **OS-independent `write.s`.** The stock `write.s` handles `O_APPEND`
   with `GET_EOF`/`SET_MARK` MLI calls inline. Moving "seek to end" into
   a helper next to `rwcommon` leaves `write.s` free of OS calls, and a
   DOS 3.3 build replaces only the helper. There is no change in
   behavior under ProDOS. (a2lib DESIGN.md 4.2)

2. **How DOS 3.3 support is selected.** DOS 3.3's `struct dirent` can't
   match ProDOS's layout (no blocks, a type byte with a lock bit, 30-
   character names), so the header and the library must be selected
   together. a2lib does that with its own `dirent.h` on the `-I` path,
   which maps the directory functions to symbols only its library
   defines, so a mismatch fails at link time. In cc65 itself, a separate
   target (`-t apple2dos33`, alongside `apple2enh`) would make it a
   single switch. Is a new target acceptable, or is a separate library
   preferred? (2, 4.3)

3. **Interrupts under DOS 3.3.** Stock `crt0` runs the module
   constructors before it patches the 6502 vectors in Language Card RAM,
   so a DOS 3.3 interrupt handler installed by a constructor gets
   overwritten. a2lib's `crt0` patches the vectors first (9 bytes of
   startup code, freed after initialisation), and its `irq.s` adds a DOS
   3.3 path beside the stock ProDOS one. Only the DOS 3.3 build needs
   this, but the reordering would be in the shared `crt0`. (6.1)

4. **Optional: newline handling for ProDOS text files.** ProDOS TXT
   files also use CR, but cc65 stores `\n` as `$0A`, so text written by
   BASIC or editors reads differently from a DOS 3.3 build. a2lib leaves
   ProDOS behavior unchanged and offers the swap as an opt-in module. If
   cc65 wanted the two to match, this is where to discuss it; I'm not
   proposing a change to the default. (5.1)

The rest of a2lib (VideoTerm and 70-column display backends, a
cooperative timer, a word-wrap filter for stdio) is outside cc65's
scope and would stay a separate library.

## Related work

<https://github.com/tsupplis/cc65-apple2-dosio> provides DOS 3.3 file
access for cc65 through its own `dos_*` API; a2lib instead implements
cc65's standard calls.

Thanks for considering it. I'm happy to adjust the approach to fit
cc65's conventions.

Scott Babcock
