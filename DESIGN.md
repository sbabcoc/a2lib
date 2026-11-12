# Apple II+ C Library: Design Record

This document records the design decisions for an Apple II+ C library
built on cc65's `apple2` target, the reasoning behind each one, and the
alternatives that were rejected. Each decision appears together with its
rationale, so that it isn't reopened without the original reasons in view.

Facts marked **(verified)** were checked against primary sources: cc65
source at commit `eebf54a` (2026-11-08), IP65 source, *Beneath Apple DOS*
(transcribed text), the ReplicApple2Plus repository (including
`HARDWARE-REFERENCE.md`), and a disassembly of VideoTerm firmware 2.4.
Section 9 lists the sources.

---

## 1. Scope and objectives

- The objective is a **full-featured C library for the Apple II+**, not
  a one-off solution for particular programs. The Uthernet II utilities
  (telnet terminal, Gopher client) are the first consumers, not the
  scope.
- Major components:
  1. DOS 3.3 file I/O (cc65's POSIX layer, stdio, and `dirent`)
  2. DOS 3.3 interrupt support
  3. Display backends selected at link time: VideoTerm, 40-column
     scrollable window, and Soft-70
  4. A text reflow output filter
- **Stock DOS 3.3 only.** Patched DOSes (Diversi-DOS, ProntoDOS, etc.)
  are not a core objective. The layer uses only the documented page-3
  vectors (`$3D6`/`$3DC` File Manager, `$3D9`/`$3E3` RWTS, `$3EA` hook
  reconnect), so patched DOSes that preserve them may work, but this is
  untested and not supported.
- **Memory is at a premium.** Optional functionality is selected at
  **link time**, never by runtime switches that keep unused code
  resident.

### Guiding principle: consistency with ProDOS, respecting DOS 3.3 idioms

> Data is stored in DOS 3.3's own on-disk format, and C programs get the
> same view of it they get under ProDOS. Where DOS 3.3 cannot express
> something ProDOS can, the operation fails **visibly**. The library
> never silently behaves differently.

Every file-layer decision below follows from this rule.

---

## 2. Packaging

**Problem:** the DOS 3.3 file layer replaces modules at link time, and the
DOS 3.3 `struct dirent` differs from ProDOS's (see 4.3). cc65 selects
headers by target defines, so the build must select both the library and
the header variant.

| Option | Pros | Cons |
|---|---|---|
| Separate target (`-t apple2dos33`) | One switch selects both header and library; they can't get out of sync | Adding a target to cc65 itself |
| Add-on library + `-D __APPLE2_DOS33__` | No change to cc65 | Linking the library without the define silently mismatches the `dirent` layout |

**Decision:** develop as an add-on library with the define, and plan to
propose a separate target upstream. As a guard during development, the
header (under the define) references a symbol that exists only in the
DOS 3.3 library, so a mismatched build fails to link instead of failing
at run time.

---

## 3. Display backends

### 3.1 Backend set (link-time selection)

| Library | Purpose | Shared 80×24 buffer |
|---|---|---|
| `vt` | Videx VideoTerm, used automatically when detected | No (the card holds the screen) |
| stock conio | 40-column default fallback, unchanged cc65 code | No |
| `c40win` | 40-column scrollable window over an 80-column screen | Yes |
| `soft70` | Hi-res "Soft-70"; **opt-in only, off by default** | Yes |

- A binary contains `vt` plus exactly one fallback. At startup, init
  probes for the card and fills a small jump table with either the
  VideoTerm routines or the fallback's routines.
- The 1,920-byte 80×24 shadow buffer is a separate object pulled in only
  by `c40win` and `soft70`.
- Soft-70 builds use their own linker config that reserves the hi-res
  page `$2000–$3FFF`. Builds without Soft-70 get that page back as
  program space, which is the main saving from keeping Soft-70 optional.
- **Why link time (not run time):** a runtime-selectable Soft-70 would
  force every binary to carry the renderer and font and to reserve the
  hi-res page whether or not it is used.

### 3.2 40-column mode: window or reflow

40-column mode supports either a scrollable window over 80 columns or
reflow.

- **Window** (`c40win`): a cursor-addressed 80×24 virtual screen. Needed
  wherever output uses cursor positioning (e.g. ANSI/VT terminal
  output, where reflow would break cursor addressing).
- **Reflow:** implemented as a **stream output filter**, not as a conio
  backend. Conio is cursor-addressed, and `gotoxy` has no meaning in
  reflowed output, so a "reflowing conio" would contradict itself. The
  filter word-wraps stream output at the screen width and works over any
  backend.
- **Panning: mechanism in the library, key bindings in the
  application.** No standard Apple II convention for panning a 40-column
  window over 80 columns was found. The II+ has only two arrow keys
  (left = Ctrl-H `$88`, right = Ctrl-U `$95`) and no Open-Apple or
  Solid-Apple keys, and which keys are free depends on the application:
  a terminal must pass Ctrl-H and Ctrl-U to the host, while a Gopher
  client can use them directly. Therefore:
  - The window **follows the cursor automatically** by default, panning
    when the cursor leaves the visible 40 columns.
  - The library exports panning functions (pan left, pan right, set
    offset, resume following the cursor) and binds no keys itself.
  - Applications choose bindings. Recommended defaults: the arrow keys
    where the application doesn't otherwise need them; behind an escape
    prefix (like telnet's `Ctrl-]` convention) where it does.

### 3.3 All output through `COUT`

- **(verified)** cc65 stdio console output already goes through `COUT`.
  In `fdtab`, fds 0–2 have `REF_NUM = $80`, and `read.s`/`write.s` check
  bit 7 and send device I/O through `RDKEY`/`COUT` (`cout.s` banks in ROM
  and calls `$FDED`). `write.s` converts `\n` (`$0A`) to `$0D` and sets
  the high bit. **Only conio** (`cputc` and the rest) writes directly to
  screen RAM.
- Therefore **each backend installs itself as the `CSW` output hook**, so
  stdio and conio take the same path. Without this, `printf` in a
  `c40win` or `soft70` build would go straight to the 40-column screen
  and bypass the 80-column buffer. The reflow filter fits into the same
  hook chain.
- **(verified)** On a non-enhanced ][, `write.s` and `cputc.s` force
  output to uppercase through `uppercasemask` (default `$DF`). The `vt`
  backend's init calls `allow_lowercase()`, since the card displays
  lowercase.

### 3.4 VideoTerm backend

**Detection (verified):** the Pascal 1.1 signature bytes are
`$C305/$C307/$C30B/$C30C` = `$38/$18/$01/$82` (HARDWARE-REFERENCE.md).
cc65's `detect80cols.s` checks the same bytes but expects `$C30C = $88`
(//e-style cards), and skips non-//e machines with a comment naming the
Videx as unsupported. `$C30C = $82` identifies the VideoTerm. Reading
`$C3xx` switches on the card's `$C800` ROM, so the probe releases it
with `STA $CFFF`.

**Entry points (decision):** the backend installs its own `CSW` routine
that calls the firmware's **Pascal 1.1 INIT and WRITE entry points**.
It does **not** use the BASIC entry (`jsr $C300`), for these reasons
(all verified from the firmware):

- The BASIC entry hooks **both** `CSW` and `KSW`. That routes stdin
  `read()` through the card's input code, which substitutes `[` for
  Ctrl-K and uses Ctrl-A to toggle case conversion. (`cgetc` reads
  `$C000` directly and isn't affected.)
- BASIC-entry output checks for a pending Ctrl-S on every character and
  pauses, **consuming the keystroke**. That breaks XON/XOFF for a
  terminal. The Pascal WRITE entry skips this check.
- The Pascal entry gives delayed wrap at column 80 (the cursor stays at
  column 80 until the next character), which suits terminal emulation.

**Init (decision):** clear the "initialized" marker at `$077B` before
the first INIT. About one power-on in 32 leaves the marker's top five
bits reading `$30`, and SETUP then skips programming the CRTC, leaving
the 80-column display dark (verified;
`VideoTermFirmwareIntegrationTest` does the same).

**Cursor and scrolling (verified):**
- The firmware keeps its cursor at `$57B` (column) and `$5FB` (row). It
  adopts the monitor's `CH` only if it's at or past the firmware's own
  column, so moving `CH`/`CV` cannot move the cursor backward. Conio
  `gotoxy` must use the `$1E` sequence, and `wherex`/`wherey` read the
  firmware's locations.
- Scrolling advances `START` (`$6FB`) and reprograms the CRTC start
  address (R12/R13). VRAM is a 2K ring buffer addressed as
  `(row × 5 + START) × 16 + column`, wrapping at 2048.
- A future direct-to-hardware `vt` backend must share these firmware
  variables, or mixing `printf` and `cputc` will put output in two
  different places. **Start with the firmware backend**; move `cputc` and
  scrolling to the hardware later only if speed requires it.

**Control codes** (firmware 2.4 dispatch table; see caveat):

| Code | Function |
|---|---|
| `$07` | Bell |
| `$08` | Backspace |
| `$0A` | Line feed |
| `$0B` | Clear to end of screen |
| `$0C` | Clear screen |
| `$0D` | CR + LF |
| `$0E` / `$0F` | Standard / alternate character set |
| `$19` | Home |
| `$1A` | Command lead-in: `0` reinitialize, `1` return to 40 columns, `2`/`3` standard/alternate set |
| `$1C` | Forward space |
| `$1D` | Clear to end of line |
| `$1E` | GOTOXY: then X+32, then Y+32; out-of-range values ignored |
| `$1F` | Cursor up |

`$00`–`$06` are ignored, so the card's graphics glyphs are reachable
only by writing VRAM directly.

**ROM variants (resolved):** the disassembly these codes came from is
of the 2.4 image distributed with MAME and the btb/80ColumnCard project
(CRC32 `BBE3BB28`). Its CRTC table at `$C8A1`
(`$7A,$50,$5E,$2F,$22,$00,$18,$1D,...`) differs from the ReplicApple2Plus
image (CRC32 `4DDBE669`); its R4/R5/R7 values give a 315-line frame,
which looks like a 50 Hz configuration. **(verified)** Replacing the 12
CRTC bytes at `$C8A1`–`$C8AC` in the `BBE3BB28` image with the values
from HARDWARE-REFERENCE.md (`7B 50 5E 29 1B 08 18 19 00 08 E0 08`)
produces CRC32 `4DDBE669` exactly. The two images are identical except
for the CRTC table, so all code, including the dispatch tables at
`$CA40`–`$CA58` and `$CBF2`–`$CBF9`, is the same, and the table above
applies to both. The 1982 manual describes `$1A` `0`/`1` as 24/18-line
modes; the ROM is authoritative.

---

## 4. DOS 3.3 file layer: architecture

### 4.1 What cc65 does today (verified)

- `fdtab`: 8 slots × 4 bytes (`REF_NUM`, `FLAGS`, `BUFFER`). `REF_NUM` 0
  means free, `$80` means console, and other values are ProDOS ref
  numbers. `open.s` allocates a 1K I/O buffer per file with
  `iobuf_alloc`.
- Every file operation goes through `callmli` (`mli.s`). When
  `__dos_type == 0` (DOS 3.3) it returns `$01`, which `oserror.s` maps
  to `ENOSYS`. That single check is the whole documented DOS 3.3
  limitation. DIO also uses `callmli`, so it fails under DOS 3.3 too;
  the current docs list only file I/O and interrupts.
- 17 modules use 16 distinct MLI calls (`OPEN`, `CLOSE`, `READ`, `WRITE`,
  `GET_EOF`/`SET_EOF`, `GET_MARK`/`SET_MARK`, `CREATE`, `DESTROY`,
  `RENAME`, `GET_INFO`/`SET_INFO`, `ON_LINE`, `SET_PREFIX`, `GET_TIME`,
  `READ_BLOCK`/`WRITE_BLOCK`).
- `read.s` has a constructor that sets `PROMPT` and `CURLIN+1` so DOS 3.3
  won't scan program output for commands. The runtime already expects to
  coexist with DOS 3.3's hooks.

### 4.2 Where the layer attaches (decision)

**Rejected: emulating the MLI in a replacement `mli.s`.** It would be the
smallest change to cc65, but:

- `opendir` opens the directory with `_open` and reads raw 512-byte
  ProDOS directory blocks with `_read`, taking the entry length, entries
  per block, and file count from header offsets `$23`–`$26`. `readdir`
  rewrites the ProDOS entry in place and returns a pointer into the
  block as the `struct dirent`. Emulation would have to generate correct
  ProDOS directory blocks from the DOS 3.3 catalog.
- `struct dirent` for the Apple II has `d_name[16]` (ProDOS's 15-character
  names). DOS 3.3 names are up to 30 characters. Emulation would have to
  truncate names, and a program couldn't reopen a file using a name from
  `readdir`. This is fixed in the public header and can't be solved
  behind `callmli`.
- `filename.s` builds every relative path by calling `ON_LINE` for the
  volume name, so emulation would need a fake volume that is stripped
  off again on every call.
- Every DOS 3.3 binary would carry translation tables for all 16 calls.

**Adopted: replace the modules above `callmli`, keeping `mli.s` as the
fallback.** Anything without a DOS 3.3 equivalent (`chdir` to
directories, `mkdir`, `rmdir`, DIO block calls) keeps failing with
`ENOSYS`, as it does today. Features are ported one by one instead of
emulating an entire OS interface.

| Replace | Keep |
|---|---|
| `open.s` (incl. `closedirect`, `freebuffer`), `rwcommon.s`, `lseek.s`, `sysremove.s`, `sysrename.s`, `stat.s`, `opendir`/`readdir`/`closedir`/`rewinddir` | `filedes.s`, `close.s`, `read.s`, `mli.s`, console device paths |

- `fdtab` works unchanged: a nonzero `REF_NUM` below `$80` indexes the
  layer's own File Manager control blocks.
- **`write.s`:** shared code except the `O_APPEND` path, which calls
  `GET_EOF`/`SET_MARK` directly. Instead of maintaining a fork, propose
  an upstream patch that moves "seek to end" into a helper next to
  `rwcommon`. Then `write.s` no longer depends on the OS, and the DOS 3.3
  build replaces only the helper.

### 4.3 `struct dirent`

The DOS 3.3 build has its own layout: `d_name[31]`, `d_type` holding the
DOS file type. This is the one public-header change (see section 2).
It's the change most likely to need discussion upstream; it goes to the
cc65 maintainers together with working code (section 9).

### 4.4 File Manager facts (verified, *Beneath Apple DOS* ch. 5–6)

- Entry: `JSR $3DC` returns the parameter list address (Y=low, A=high);
  `JSR $3D6` calls the File Manager. X=0 on OPEN creates the file if it's
  missing; X≠0 does not.
- **Buffers are supplied by the caller on every call:** a 45-byte work
  area, a 256-byte track/sector list buffer, and a 256-byte data buffer,
  557 bytes per open file. **Decision:** allocate them with the existing
  `iobuf` mechanism (smaller than ProDOS's 1K). The layer does not use
  DOS's MAXFILES buffer chain, so it isn't limited by MAXFILES.
- A POSITION is required before the first READ or WRITE.
- A range WRITE takes the byte count **minus one**.
- RENAME takes the new name's address at bytes `02/03`.
- CATALOG only prints to the output device. **`readdir` reads the VTOC
  and catalog sectors directly through RWTS (`$3D9`).**
- Catalog entries store the type byte (bit 7 = locked), a 30-character
  name, and a length **in sectors only**. No byte length is stored.
- **File-type codes differ:** the File Manager uses `$08`=R and `$10`=S,
  while catalog entries use `$08`=S and `$10`=R. The type mapping must
  use the right table in each place.
- `$3EA` reconnects DOS's keyboard and screen hooks.

---

## 5. DOS 3.3 file layer: semantics

### 5.1 T (text) files

**Reference behavior (verified):** cc65's ProDOS file I/O passes bytes
through unchanged. A C program writing `"HI\n"` to a ProDOS TXT file
stores `48 49 0A`. The newline and high-bit conversion applies only to
console output.

**Decisions:**

- **High bit:** set on write, stripped on read, for T files only. C code
  sees exactly the bytes it would see under ProDOS, and the disk holds
  the high-bit text DOS 3.3 expects.
- **Nulls round-trip.** A C `\0` is stored as `$80` and read back as
  `$00`. Every byte the layer writes is `$80` or higher, so a literal
  `$00` on disk only ever means end of data or unwritten padding.
- **End of file** is the first `$00` on disk.
- **Bytes `$80`–`$FF` are rejected.** A write containing any byte with
  bit 7 set fails with `EINVAL`. T files therefore hold 7-bit data;
  programs that need 8-bit data use B files, which pass all bytes
  through unchanged.
- **`O_TRUNC`** deletes and recreates the file with the same type, since
  the File Manager can never shorten a file.
- **Newlines follow the OS idiom: lines end with CR.** On write, `$0A`
  and `$0D` are **swapped** (then the high bit is set), so C's `\n` is
  stored as `$8D` and a literal `\r` as `$8A`. On read, the swap is
  reversed. Because it's a swap rather than a one-way translation, every
  byte still round-trips exactly, offsets still map 1:1 (so `lseek` and
  record addressing are unaffected), and Applesoft reads C-written text
  line by line. This is the approach classic Macintosh C compilers took
  on another CR-native system.
- **ProDOS keeps stock cc65 behavior (decision).** ProDOS TXT files also
  use CR line endings, but cc65's ProDOS file I/O stores C's `\n` as raw
  `$0A`. This project maintains backward compatibility and does not
  change ProDOS behavior. The resulting difference:
  - Files a C program writes and reads back itself behave the same on
    both DOSes (both round-trip exactly).
  - Text written by **other** programs (BASIC, editors) differs: under
    DOS 3.3, C reads its CR line endings as `\n`; under stock ProDOS, C
    reads them as `\r`.
  - **Opt-in ProDOS swap:** the library provides a link-time module that
    applies the same swap to ProDOS TXT files, for programs that want
    identical behavior on both DOSes. Because it is opt-in, it imposes
    nothing on existing programs.
  - The swap for ProDOS is raised in the upstream proposal to the cc65
    maintainers (section 9). If cc65 adopts it, the two builds converge
    and the opt-in module becomes unnecessary.

**Rejected alternatives for 8-bit data in T files:**

- **Masking (silently clearing bit 7).** This matches what DOS 3.3 itself
  does, but data gets corrupted without any error, which violates the
  guiding principle.
- **UTF-8 or another escape encoding.** The existing codec works because
  it maps one byte to one byte. Any variable-length encoding loses that:
  - File offset *n* would no longer be disk offset *n*.
    `lseek(fd, n, SEEK_SET)` would have to decode from the start of the
    file, making seeks proportional to file size, and record × length
    addressing for random-access files would break.
  - Overwriting a 1-byte character with a 2-byte sequence in the middle
    of a file would shift everything after it, which the File Manager
    can't do.
  - UTF-8 doesn't actually fit. Every UTF-8 byte above ASCII is `$80` or
    higher, which already means high-bit text on disk. The only free disk
    values are `$01`–`$7F`, so it would be a custom escape scheme with
    UTF-8's costs and none of its compatibility.
  - Applesoft and other DOS 3.3 programs would read the escaped bytes as
    stray control characters, a silent difference of exactly the kind the
    guiding principle forbids.

  What rejection costs is small: 8-bit data in T files is rare even under
  ProDOS, and B files handle that case.

### 5.2 Random-access T files

In BASIC, `OPEN F,L100` declares a 100-byte record length, and READ/WRITE
take a record number, which DOS turns into an offset of record × 100. The
record length **is not stored on disk**, so the layer can't recognize
such files anyway.

**Decision:** no record-length API; byte offsets only.
`lseek(fd, r * 100L, SEEK_SET)` does what BASIC's record addressing does.
The layer converts large offsets into the File Manager's record and
byte-offset fields internally. The T-file rules in 5.1 already handle
these files: unwritten records are sparse and read as zeros, and each
record's zero padding ends a read, acting as a record terminator.

### 5.3 B (binary) files

**Reference behavior:** ProDOS keeps a BIN file's load address in the
aux type and its length in the EOF, with no header in the data.

**Decisions:**

- **Hidden header:** `read`, `write`, and `lseek` never see the 4-byte
  address/length header. The layer adds 4 internally.
- **Load address:** `__auxtype` sets it at create time, and `stat`
  returns it, as under ProDOS.
- **Length:** taken from the header, so EOF is exact and
  `SEEK_END`/`O_APPEND` need no scan. The header is updated on close.
- The file still `BLOAD`s and `BRUN`s normally.
- **A and I files** have a 2-byte length header and get the same
  treatment.

### 5.4 File types on create

Reuse `__filetype` with ProDOS codes so source stays portable: `$04`→T,
`$06`→B, `$FC`→A, `$FA`→I, `$FE`→R. The default stays `$06` (B), as in
stock cc65. Any other `__filetype` has no DOS 3.3 equivalent, so
`open(..., O_CREAT)` fails with `EINVAL`.

Files of types other than T, A, I and B (R, S, and the "new" A and B
types) are transferred raw. They have no end recorded below sector
granularity, so reads return data up to the end of the last sector, and
`O_APPEND` fails with `EINVAL` instead of appending after padding.

### 5.5 Names and locations

ProDOS addresses files by pathname (`/VOLUME/NAME`). DOS 3.3 names carry
no location, but the File Manager needs slot and drive in every call, so
some mechanism is required. **Decision:** use DOS 3.3's own syntax.

- **Default:** a plain `"MYFILE"` uses DOS's last-used values. On 48K DOS
  3.3 these are at `$AA66` (volume), `$AA68` (drive), and `$AA6A` (slot),
  each 2 bytes (verified, *Beneath Apple DOS* ch. 8).
- **Explicit:** `"MYFILE,S6,D2,V254"`, with any combination of suffixes,
  as typed at the DOS prompt, in `open`, `remove`, `rename`, and `stat`.
- **Directories:** `opendir(",D2")` lists drive 2. `chdir(",S6,D2")`
  changes the defaults, which corresponds to ProDOS's prefix.
- Names are up to 30 characters and must start with a letter; there are
  no subdirectories. When no fdtab slot is free, `open` fails with
  `EMFILE`.
- **Case (decision):** names are converted to uppercase, because ProDOS
  treats names case-insensitively, so `open("hello")` finds `HELLO` under
  both DOSes.
- **Storage:** names are stored with the high bit set and padded with
  `$A0` to 30 bytes, the way DOS's own command parser fills its name
  buffer (*Beneath Apple DOS* ch. 8, `A095`).
- **Sticky S and D:** an explicit `S` or `D` suffix becomes the new
  default, as it does for DOS commands. `V` is not sticky; DOS resets it
  to 0 for every command (ch. 8, `A0D1`).

### 5.6 Error mapping

**Decision (made during implementation):** File Manager return codes are
translated into the **equivalent ProDOS 8 error codes** at the boundary
(`fm_maperr` in `fm.s`). The stock `close.s` passes errors to
`___mappederrno`, which uses the ProDOS table in `oserror.s`, so this
translation lets the whole stock errno machinery, including `_stroserror`
messages, work unchanged. It also means `__oserror` holds the same value
under both DOSes for the same failure, which follows the guiding
principle. No DOS 3.3 message table is needed.

| File Manager code | Meaning | `errno` | ProDOS analog |
|---|---|---|---|
| `02` / `03` | Bad call / sub-call type | `EINVAL` | — |
| `04` | Write protected | `EACCES` | `$2B` |
| `05` | End of data | (end of file, not an error) | `$4C` (unmapped) |
| `06` | File not found | `ENOENT` | `$46` |
| `07` | Volume mismatch | `ENOENT` | `$45` |
| `08` | I/O error | `EIO` | `$27` |
| `09` | Disk full | `ENOSPC` | `$48` |
| `0A` | File locked | `EACCES` | `$4E` |


---

## 6. DOS 3.3 interrupts

**(verified)** cc65's `initirq` simply asks the ProDOS MLI to allocate an
interrupt and prints "FAILED TO ALLOC INTERRUPT" otherwise. `crt0.s`
already installs an IRQ forwarding routine in the Language Card vectors
for non-ProDOS programs. **Decision:** a DOS 3.3 `initirq`/`doneirq` that
hooks the monitor's IRQ vector at `$3FE`, chaining the previous handler,
selected at link time like the other modules.

---

## 7. Runtime environment (verified)

- There is no `apple2-dos33.cfg` in current cc65; there is one
  `apple2.cfg`. `crt0.s` sets the C stack from Applesoft's `HIMEM` at run
  time (except under ProDOS without BASIC.SYSTEM), so MAXFILES changes
  are handled automatically. `__HIMEM__` (default `$9600`) only bounds
  program size at link time.
- Under DOS 3.3 the whole Language Card is free (`__LCADDR__=$D000`,
  `__LCSIZE__=$2FFC`), but only if a card is present. Builds meant for a
  stock 48K ][+ must keep the `LC` segment empty.
- ProDOS builds require 64K; DOS 3.3 builds run on 48K.
- **IP65:** `uthernet2.s` includes `w5100.s`; neither contains interrupt
  code, so the driver polls and works under DOS 3.3 as-is.

---

## 8. Testing

- **Emulator:** ReplicApple2Plus. Headless JUnit 5 tests already run the
  real system ROM and VideoTerm firmware, inject keystrokes, and read the
  80-column text with `VideoTermRenderer.text(card)`. Disk II and DSK/WOZ
  image tests exist too. **Remaining work:** a fixture that boots a disk
  image, runs a binary, and captures the screen.
- **Differential testing:**
  - Build the same test programs for ProDOS and DOS 3.3 and compare
    results, with ProDOS as the reference for file-layer behavior.
  - For a future direct-hardware `vt` backend, compare its screens with
    the firmware backend's. The firmware's behavior comes from Videx, so
    it serves as an independent reference against shared
    misunderstandings of the spec.
- **AppleCommander** provides an independent check of what actually ends
  up on disk images.
- **Machine configs:** ProDOS tests need the language card (slot 0) or
  the Saturn card. The VideoTerm must be in slot 3 (firmware 2.4
  requirement).

---

## 9. Open items

- None at present.

**Resolved since the first draft:**

- VideoTerm control dispatch: identical in both 2.4 images (section 3.4).
- Window panning: automatic by default; library functions, application
  bindings (section 3.2).
- Text newlines: follow the OS idiom via a lossless `$0A`/`$0D` swap
  (section 5.1).
- **cc65 maintainers are contacted with working code**, not before
  implementation. This covers the `dirent` header change, the
  OS-independent `write.s` refactor, the proposed separate target, and
  the `$0A`/`$0D` swap for ProDOS TXT files.
- ProDOS behavior is unchanged by default (backward compatibility); the
  swap is available as an opt-in module (section 5.1).

## 10. Implementation status

### 10.1 Increment 1: open, close, read, write

Files (repository root):

| File | Role |
|---|---|
| `libsrc/dos33/fm.inc` | File Manager parameter list, call codes, control block layout |
| `libsrc/dos33/fm.s` | Call wrapper (ROM banked in), buffer setup, read/write helpers, error translation |
| `libsrc/dos33/fmname.s` | Name and suffix parsing (5.5) |
| `libsrc/dos33/open.s` | Replaces stock `open.s`: `open`, `closedirect`, `freebuffer`, exit-time close |
| `libsrc/dos33/rwcommon.s` | Replaces stock `rwcommon.s`: T-file codec, hidden headers, raw transfer |
| `libsrc/dos33/write.s` | Stock `write.s` with the append path calling `seekend` (4.2) |
| `libsrc/dos33/seekend.s` | Seek to end for `O_APPEND` |
| `libsrc/dos33/filedes.inc`, `mli.inc` | Unmodified copies from cc65 (see `VENDORED.md`) |
| `test/filetest.c` | Tests for every decision in section 5 |
| `Makefile` | Builds `lib/apple2-dos33.lib` and the tests |

Programs link the library before cc65's own:
`cl65 -t apple2 -o prog prog.c lib/apple2-dos33.lib`.

**Verified by building:** all modules assemble, and the test program
links with `open.o`, `rwcommon.o` and `write.o` from this library and
`close.o`, `read.o`, `filedes.o` and `mli.o` from stock cc65, with no
duplicate symbols. Size: 2,050 bytes of code and data, plus 567 bytes of
heap per open file (stock ProDOS: 1K per file).

**Implementation details:**

- `fdtab[fd].REF_NUM` holds the slot's fdtab offset ORed with `$40`:
  nonzero and below `$80`, so stock modules treat it as a file, and
  `rwcommon` recovers the slot from it. (The plain offset can be 0 if
  stdin has been closed, which would mark the slot free.)
- Header files (A, I, B) track their logical position and length in
  the control block. The header's length is rewritten on close when it
  changed; files closed at exit are handled by a destructor, as stock
  cc65 does for ProDOS.
- B-file lengths are 16-bit; a write that would pass 65,535 bytes fails
  with `ENOSPC`.
- T files track a 16-bit logical position, used to write over the
  terminator after reading to the end. Positioning in T files beyond
  64K is not supported in this increment.
- T-file reads and raw-file reads go byte by byte, because a range READ
  that runs into the end of the data doesn't report how many bytes it
  transferred. B-file reads use range READs clipped to the recorded
  length.

### 10.2 To confirm on real DOS 3.3

These follow the sources but have not been run yet. Each is isolated so
it can be corrected in one place.

- **Range WRITE length:** *Beneath Apple DOS* says a range WRITE takes
  the count minus one. Implemented as `FM_WRITE_ADJUST` in `fm.inc`.
- **New sectors are zero-filled:** T files rely on a `$00` following the
  last byte written. If the File Manager doesn't clear new data sectors,
  the end of a T file would be lost.
- **OPEN output type byte:** assumed to use File Manager type codes, with
  bit 7 as the lock flag (masked off).
- **POSITION offsets:** assumed to be whole-file byte offsets when the
  record number is 0 and the file was opened with record length 0.
- **Language Card banking:** the File Manager is called with ROM banked
  in and LC bank 2 restored afterward, the same pattern `rdkey.s` uses.

### 10.3 Next increments

- `lseek`, `remove`, `rename`, `stat`
- Directories: `opendir`/`readdir` via RWTS, the DOS 3.3 `struct dirent`,
  and the link guard (section 2)
- DOS 3.3 interrupts (section 6)
- Display backends (section 3)
- Emulator test fixture (section 8)

## 11. Sources

- cc65, commit `eebf54a`: `libsrc/apple2/` (`filedes.*`, `open.s`,
  `read.s`, `write.s`, `rwcommon.s`, `lseek.s`, `mli.s`, `oserror.s`,
  `opendir.s`, `readdir.s`, `filename.s`, `diocommon.s`, `irq.s`,
  `crt0.s`, `cout.s`, `detect80cols.s`), `include/dirent.h`,
  `cfg/apple2.cfg`, `doc/apple2.sgml`
- IP65: `drivers/uthernet2.s`, `drivers/w5100.s`
- *Beneath Apple DOS*, chapters 4, 5, 6, 8 (transcribed text,
  github.com/knghtbrd/beneath-apple-dos)
- ReplicApple2Plus: `HARDWARE-REFERENCE.md` §3,
  `VideoTermFirmwareIntegrationTest`
- Videx VideoTerm firmware 2.4 disassembly and ROM image `BBE3BB28`
  (6502bench SourceGen; github.com/btb/80ColumnCard)
- Videx VideoTerm Installation and Operation Manual, 3rd ed. (1982)
