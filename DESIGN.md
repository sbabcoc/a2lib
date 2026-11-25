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
- **DOS 3.3 only (decision, 10.22).** Programs linked with a2lib run
  under DOS 3.3, not ProDOS: the modules carry no ProDOS paths and no
  `__dos_type` checks, as a separate cc65 target would. Build with stock
  `apple2.lib` for ProDOS. Raised by Colin Leroy-Mira's review on
  cc65/cc65#3050: ProDOS code kept in DOS 3.3 modules is dead weight.
- **Stock DOS 3.3 only.** Patched DOSes (Diversi-DOS, ProntoDOS, etc.)
  are not a core objective. The layer uses only the documented page-3
  vectors (`$3D6`/`$3DC` File Manager, `$3D9`/`$3E3` RWTS, `$3EA` hook
  reconnect), so patched DOSes that preserve them may work, but this is
  untested and not supported.
- **Memory is at a premium.** Optional functionality is selected at
  **link time**, never by runtime switches that keep unused code
  resident.

### Guiding principle: cc65's generic interface, DOS 3.3's own specifics

> Data is stored in DOS 3.3's own on-disk format. C programs get cc65's
> generic interface (POSIX calls, paths and `errno` values) as on any
> cc65 target. Everything OS-specific (`__oserror` values, file names,
> file types) is DOS 3.3's own, written as if there were no ProDOS
> library. Where DOS 3.3 cannot express something, the operation fails
> **visibly**. The library never silently behaves differently.

Every file-layer decision below follows from this rule.

**Revised after review (cc65/cc65#3050).** The first version of this
principle was "consistency with ProDOS": C programs were to get the same
view of DOS 3.3 they get under ProDOS, down to ProDOS error codes in
`__oserror`. Oliver Schmidt, who wrote much of cc65's Apple II library,
pointed out that cc65's OS-specific codes are what the name says, so one
OS shouldn't emulate another's. He also said the generic, POSIX side is
what matters to a cc65 program, including path names. The principle now
follows that: DOS 3.3's error numbers (5.6, increment 12), file types
(5.4, 5.8, 5.9, increment 13) and POSIX paths (5.5, 5.9, increment 14).

### Code conventions

The readability passes (10.16 to 10.18) applied these; every change
follows them, so the code stays as readable as they left it.

- **Names, not raw values.** A value that means something gets a name,
  defined once, where the modules that need it can include it:
  - `libsrc/dos33/machine.inc`: Apple II and DOS addresses (language card
    switches, `MON_COUT`, `DOS_CONNECT`, `BASIC_BUF`, the stack page) and
    high-bit characters (`HI_CR`, `HI_LF`, `HI_BS`, `HI_SPACE`,
    `HI_CTRL_D`, `HIBIT_OFF`)
  - `libsrc/dos33/fm.inc`: the File Manager, RWTS and catalog layouts;
    file types (`FMT_*`); `__oserror` values (`DOSERR_*`, `LIBERR_*`)
  - `libsrc/s80/s80.inc`: the shared 80 × 24 model (`S80_BUF_XOR`)
  - `include/`: what C programs use (`DOS33_T_*`, `DOS33_LOCKED`)

  A module's own values (a table length, a timing constant) are named in
  the module. One name per value: no second name for the same thing.
  cc65's own names (`apple2.inc`: `DOSWARM`, `CURLIN`, `PROMPT`, ...) come
  first where they exist.
- **Shared storage gets a name for what it holds (10.39).** cc65's
  zero-page cells (`ptr1`-`ptr4`, `tmp1`-`tmp4`, `sreg`) are named in a
  "Shared storage" block after the module's includes (`buffer = ptr1`),
  as stock modules such as `vfscanf.s` and `lzsa1.s` do. A cell with two
  jobs in one module gets a name for each, used where it does that job.
  `sreg` keeps its name where it holds a `long` result's high word, as
  the calling convention names it.
  Names that several modules share are defined once: `fm.inc` has
  `fm_parmlist` (`ptr3`) and `ctlblock` (`ptr4`), `dir.inc` has `dirptr`
  (`ptr1`). Those are text macros (`.define`), because a `=` alias
  imports its cell even in a module that never uses it, which
  `samebytes.sh` reports; a `.define` name must be unique across the
  sources, as it replaces the word wherever it appears. Vendored modules
  keep stock's names, so they stay easy to compare.
- **Addresses by name.** Code names every soft switch, ROM entry point
  and fixed location: cc65's `apple2.inc` where it has a name that says
  what the location does (`KBD`, `CH`), else `libsrc/dos33/machine.inc`
  (`MON_COUT`, `MON_RDKEY`), vendored modules included. The language card
  switches are all a2lib's, named for what each does to reads and writes
  (`LC_BANK2_RO`, `LC_ROM_WRAM`, `LC_ROM_RO`, `LC_BANK2_RW`): cc65 names
  only two, and its `ROMIN` and `LCBANK2` don't say that both write-enable
  RAM. The exception is `$0103,x` after `tsx`, an offset into the stack
  frame.
- **File headers.** Each file opens with its authors, then a summary of
  what it holds, in sentences, ending with a pointer to the design: "For
  details, see section 5.9 of DESIGN." File headers name no other source
  file and repeat no C signature; the generated font names its generator,
  where it is edited.
- **Routine headers (10.40, 10.49, 10.50).** Every exported routine, and each
  internal one worth a name, has a header after a 78-column rule: what it
  does, without its name (the label follows), then `Signature:` (the C
  declaration, for a function C calls; no `void` in an empty argument
  list), `Overrides:` (the cc65 function or symbol it takes the place of,
  or the C name a2lib's headers map to it), `Prepare:`, `Input:` and
  `Output:` (one line per value: where it is, its type, what it means),
  `Changes:` (registers, flags and storage changed besides the outputs,
  and other effects) and `Note:`, each only where it applies: no `Input:
  none` or `Output: none`. `Prepare:` names what the caller must have
  called first for the inputs to be valid: C functions with `()`
  (`open()`, `opendir()`, `a2_timer_start()`), routines without
  (`fm_begin`), in order. It names no helper's own caller, which sets up
  the helper's inputs as part of its work, and nothing that runs by
  itself, such as a constructor. Inputs describe values, not where they
  came from. What a C programmer already knows is left out. Types are C's
  where C sees the value (`int`, `char*`, `unsigned`), else `byte`,
  `word`, `flag` or `T*`. A module's storage is given by its name; another
  module's cells as `ptr1 (fm_name)`. Registers that hold one 16-bit or
  32-bit value are named together, high byte first:

  | Notation | Meaning |
  |---|---|
  | `X:A` | X high, A low: cc65's order, for every C function and a2lib interface |
  | `A:X` | A high, X low: cc65's `reset` only |
  | `A:Y` | A high, Y low: DOS 3.3's `LOCATE` calls, and RWTS's IOB |
  | `sreg:X:A` | a `long`: `sreg` the high word, X:A the low |

  The meaning column says what the value is in words, such as "directory
  object pointer", without repeating the C parameter's name. The stack
  is mentioned only where its use is out of the ordinary, such as
  exec()'s reset. Vendored modules get headers too, as comments that
  leave stock's code as it is. The guards and selectors define no
  routine, so their file headers are all they have.
- **Labels.** An anonymous label is only for a jump to the nearest one
  (`:+`, `:-`). A jump past another label (`:++`, `:--`), including the
  outer loop of a nested pair, gets a named label (`@row`, `@col`).
- **Vendored modules** (`libsrc/dos33/VENDORED.md`) keep the stock code
  they still use untouched, so they stay easy to compare with cc65's;
  their ProDOS paths are removed. a2lib's additions inside them follow
  these conventions, and `VENDORED.md` lists each module's changes. The same goes for backend modules based on stock ones
  (`cgetc.s`, `rdkey.s`, `cout.s` and the like).
- **Generated files** are changed through their source: `s70/font.s` comes
  from `tools/s70font.txt`.
- **Comments** say what code does and why, with a reference where the
  reason is DOS's or the hardware's ("Beneath Apple DOS" chapter and
  address, a DESIGN.md section). A comment that the code has outgrown is
  corrected in the same change.
- **Every change** updates DESIGN.md: the decision where it's discussed,
  and a record in section 10 with its files and how it was verified. New
  behavior gets tests; `make emutest` and `make simtest` pass before a
  commit.
- **Changes meant to touch only names, comments and layout** are proven
  byte-identical with `bash tools/samebytes.sh [REV]`: it builds REV and
  the working tree and compares every module's generated bytes, every C
  test's generated assembly, and every linked program. Changes to scripts
  and the Makefile, which generate nothing to compare, are checked by
  what they do (`make -n`, or the script run against stand-ins).

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

**Decision:** develop as an add-on library, and plan to propose a
separate target upstream.

**Header selection (revised in increment 3):** instead of a
`-D __APPLE2_DOS33__` define, a2lib ships `include/dirent.h`, which
shadows cc65's when a2lib's include directory is passed with `-I`
(verified: for `#include <dirent.h>`, a header in a `-I` directory takes
precedence over cc65's). Passing `-I include` is then the single switch
that selects the DOS 3.3 header; there is no separate define to keep in
sync with it. The header is needed only by programs that use the
directory functions.

**Link guard (revised in 10.33):** the header maps `opendir`, `readdir`,
`closedir` and `rewinddir` to `_opendir_a2lib` and the like, which exist
only in `a2lib-dos33.lib`. The names follow the principle that a
function's name doesn't name an operating system; they name the library
whose `struct dirent` the caller was compiled with. The DOS 3.3 modules
(`opendir.s`, `readdir.s`, `closedir.s`, `rewinddir.s`) take the place of
cc65's of the same names.

- Header without the library: the link fails, naming `__opendir_a2lib`
  and the others the program calls (verified).
- Library without the header: the program calls `opendir`, which `cl65`
  would find in cc65's own `apple2.lib`, appended after the core, and run
  ProDOS code on the DOS 3.3 layout. Guards in the core
  (`libsrc/guard/opendir_stock.s` and the like, 4.2) define those names
  instead, so the link fails, naming `opendir_needs_a2lib_dirent_h`
  (verified; until 10.33 the stock modules were in the core and failed at
  run time with `EINVAL`).

Either way, the DOS 3.3 `struct dirent` is never mixed with the ProDOS
implementation.

**The add-on library is a complete library (decision, from the first run
of increment 2):** `lib/a2lib-dos33.lib` is a copy of the installed
cc65's `apple2.lib` with the DOS 3.3 modules replacing the stock modules
of the same name (`ar65 r`) and the new modules added. A library holding
only the replacement modules is not enough, because ld65 scans each
library once, in command-line order, and pulls in only modules that
satisfy references open at that moment. A stock module reached through
another stock module is then resolved inside `apple2.lib`:

- `remove()` is only in `apple2.lib`, so `remove.o` is pulled from there,
  and its reference to `__sysremove` resolves to the stock module. The
  first run of the increment 2 tests failed every remove/rename check
  this way (stock `__sysremove` returns `ENOSYS` under DOS 3.3).
- The same applies to `fopen` → `open`: a program using only stdio got
  stock `open.o` and `close.o` (confirmed with a link map).

With the complete library listed first, every symbol resolves inside it,
and cc65's own `apple2.lib`, which `cl65` still appends, contributes
nothing. The link command is unchanged. Because the library embeds the
stock modules of the cc65 it was built with, **it must be rebuilt after
updating cc65**; the Makefile locates the installed `apple2.lib` through
`cl65 --print-target-path`.

**What stock cc65 doesn't have is in add-on libraries (decision, 10.31).**
The core, `a2lib-dos33.lib`, is stock `apple2.lib` with only the DOS 3.3
file layer, its interrupt support and exec, and the link-time guards
(4.2). New functionality is in libraries of its own:

| Library | Contents |
|---|---|
| `a2lib-timer.lib` | The cooperative timer and software clock (6.3): `timer.s`, `tick.s`, `gettime.s`, `settime.s`, and the ticking `cgetc.s` and `kbhit.s` (`libsrc/timer`); copies of stock modules (below) |
| `a2lib-reflow.lib` | The reflow filter (3.7): `reflow.s`, the vectored `cout.s`, `viewport.s` (`libsrc/reflow`) |
| `a2lib-vt.lib` | The VideoTerm backend (3.5), with `tick.s` and `kbhit.s`; copies of stock modules |
| `a2lib-soft70.lib` | The VideoTerm with Soft-70 (3.8), with `tick.s`, `kbhit.s` and `timer.s`; copies of stock modules |

A link line lists the add-ons' selectors (below), then the add-ons in
the order display, reflow, timer, then the core. An add-on's modules are
new, or take the place of modules of the same names in libraries listed
after it: the core's (a display library's `cputc.s`), or another add-on's
(its `cout.s` and `viewport.s`, `a2lib-reflow.lib`'s). The display
libraries carry the timer modules they use, identical to
`a2lib-timer.lib`'s: both the tick hook and `kbhit`, and Soft-70's the
timer, which its gauge and cursor use, so a Soft-70 program needs the
timer library only for the clock. Without it, `clock_gettime` and
`clock_settime` reach the core's guards and fail to link. A program using none of them links the core alone and gets stock
cc65's conio, `cgetc`, `kbhit` and `COUT`.

**Copies and selectors (revised in 10.32).** ld65's single scan, which
made the core a complete library, applies to the add-ons too: listed
ahead of the core, an add-on supplies only what is open when ld65 reaches
it, the program's own calls. A program calling `cputs` but not `cputc`,
linked with `a2lib-vt.lib`, would get stock `cputs` from the core, and
then stock `cputc` with it. Copying the whole core into each add-on, as
the core copies `apple2.lib`, would remove the problem but make the
add-ons alternatives, not additions. Two narrower means cover it:

- **Copies.** Each add-on holds copies of the core modules that import a
  symbol it defines in place of the core, and of the modules that import
  theirs, and so on: for a display library, the 13 stock conio modules
  `cputs`, `cprintf`, `vcprintf`, `cgets`, `cscanf`, `vcscanf`, `cclear`,
  `chline`, `cvline` (`dynchline`, `dyncvline`), `cputhex`, `scrsize`,
  and cc65's debugger (`dbg`, `dbgsupp`); for the timer, `cgets`,
  `cscanf`, `vcscanf`, `time` and the debugger. A copy is taken when
  ld65 scans the add-on, and its calls resolve there, since ld65 keeps
  taking modules from a library until none resolves an open reference.
  `tools/stockcopy.py` works out the set from the libraries with `od65`
  and adds the core's own object files, unchanged, when the Makefile
  builds the add-on; rebuilding after updating cc65 refreshes them with
  the core.
- **Selectors.** What can't be copied is pulled in by a selector,
  `lib/a2lib-<name>.o` (`libsrc/select`), an object of `.forceimport`s
  that, linked whole, opens those names before ld65 reads the first
  library: the add-on's modules that a later module imports where that
  module isn't copied. a2lib's `write` and `read` call `COUT` and
  `RDKEY`, and all of stdio reaches them; `reflow.s`, in an add-on, calls
  `_wherex` and `a2_viewport`. So a display library's selector forces
  `COUT`, `RDKEY`, `_wherex` and `a2_viewport`; the reflow library's,
  `COUT`; the timer's, nothing. The timer's exists so that every add-on
  is linked the same way.

**A display library without its selector fails to link.** `vt.s`, which
every module of the display libraries imports from, imports
`a2lib_display_needs_selector_object`, which only the display selectors
define. Without the selector, ld65 names that symbol; with two display
libraries, it reports it as a duplicate. A program that links nothing of
the display library (only stdio, and no selector) can't be caught this
way: nothing of the library is linked at all, as if it weren't listed.
Leaving out the reflow or timer selector changes nothing: `reflow_on`
pulls in the reflow library's `COUT`, and the timer's selector is empty.

`test/selcheck.py`, run by `make linktest`, computes from the built
libraries which modules each selector must pull in and checks the
selector against it, at the level of modules: one missing would be a
silent fallback to stock, one more would cost every program its size.
A missing copy shows as a module the selector would have to pull in. It
also checks parity: a module taking the place of another defines every
symbol of it that any module imports, so the other can't be linked
beside it. A module identical to a later add-on's (the bundled timer
modules) takes nobody's place. `make linktest` also links programs that
reach each add-on only through stock modules and checks their maps.

The cost is what the selector forces in for programs that don't use it:
10 to 72 bytes for a display library (`COUT`, `RDKEY`, `wherex`,
`viewport`), nothing for the others. Forcing every module that a core
module may import, without copies, cost up to 556 bytes (10.31, 10.32).

---

## 3. Display backends

### 3.1 Backend set (link-time selection)

| Library | Purpose | Shared 80×24 buffer |
|---|---|---|
| `vt` | Videx VideoTerm, used automatically when detected | No (the card holds the screen) |
| stock conio | 40-column default fallback, unchanged cc65 code | No |
| `c40win` | 40-column scrollable window over an 80-column screen (removed in 10.36) | Yes |
| `soft70` | Hi-res "Soft-70"; **opt-in only, off by default** | Yes |

- A binary contains `vt` plus exactly one fallback. At startup, init
  probes for the card and fills a small jump table with either the
  VideoTerm routines or the fallback's routines.
- The 1,920-byte 80×24 shadow buffer and the screen model around it
  (cursor, wrap, scrolling, panning, the gauge's timer) are shared code
  in `libsrc/s80/`, linked only by `soft70` (and by `c40win` until it
  was removed, 10.36); the backend supplies the display (3.8,
  "Implementation").
- Soft-70 programs are linked with `--start-addr 0x4000`, so the program
  sits above the hi-res page `$2000–$3FFF` (decided in increment 9, in
  place of an own linker config: 3.8). Builds without Soft-70 get that
  page back as program space, which is the main saving from keeping
  Soft-70 optional.
- **Why link time (not run time):** a runtime-selectable Soft-70 would
  force every binary to carry the renderer and font and to reserve the
  hi-res page whether or not it is used.

### 3.2 40-column mode: window or reflow

40-column mode supports either a scrollable window over 80 columns or
reflow.

- **Window** (`c40win`): a cursor-addressed 80×24 virtual screen. Needed
  wherever output uses cursor positioning (e.g. ANSI/VT terminal
  output, where reflow would break cursor addressing). Removed in 10.36:
  it showed half the 80 columns, in 20-column steps; Soft-70 (3.8) is
  the cursor-addressed 80×24 screen without a VideoTerm.
- **Reflow:** implemented as a **stream output filter**, not as a conio
  backend. Conio is cursor-addressed, and `gotoxy` has no meaning in
  reflowed output, so a "reflowing conio" would contradict itself. The
  filter word-wraps stream output and works over any backend.
- **The window and reflow are not alternatives to each other in the
  library;** each program chooses per kind of output. Cursor-addressed
  output (a terminal session, a full-screen menu) has fixed positions and
  can't be reflowed, so it needs the window to be shown on 40 columns.
  Running text (a Gopher document) has no fixed layout, so reflowing it
  changes only readability. One program may use both, e.g. a Gopher
  client that pans for its menus and reflows documents.
- **Reflow is activated at run time (decision).** Programs turn it on
  and off as they go (`reflow_on`, `reflow_off`), for example reflowing
  documents but not menus. Memory compared (estimates before
  implementation: 150-250 bytes of code, an 80-byte word buffer in BSS):

  | Approach | Programs that reflow | Programs that don't |
  |---|---|---|
  | Always linked, switched at run time | Filter + flag | Filter + flag, unused |
  | Link-time module (fixed for the run) | Filter | Nothing |
  | **Linked on demand by calling `reflow_on()`** | Filter + switch | Nothing, or a few bytes of hook in the output path |

  With cc65's linker, a module is linked only if referenced, so putting
  the filter in the same module as `reflow_on`/`reflow_off` gives runtime
  control at link-time cost: programs that never call them don't link
  the filter. The remaining design work is the hook point. The stock
  library's console output goes through `CSW`, so a filter can chain
  itself there; but the VideoTerm and window libraries' `cout.s` call
  `vt_write`/`win_cout` directly, bypassing `CSW`, so they need a hook
  vector (or to route through `CSW`, at a small speed cost).
  **Resolved in 3.7:** a vector in every library's `cout.s`, the one
  routine all stdio console output passes through; not `CSW`, which DOS
  3.3 manages (3.5).
- **Reflow breaks lines at the viewport width (decision):** the width
  actually visible, 80 on the VideoTerm and 40 in the window and on the
  stock screen. In the window, the program's screen is 80 columns wide
  but only 40 are shown; breaking reflowed text at 80 would leave half of
  each line out of view, forcing the reader to pan back and forth, which
  defeats the purpose of reflowing. A program may still pass an explicit
  width (`reflow_on(width)`, with 0 meaning the viewport width), e.g. 80
  to break lines exactly as on the VideoTerm.
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
  `soft70` build would go straight to the 40-column screen
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

### 3.5 VideoTerm implementation (increment 5)

**Packaging.** `lib/a2lib-vt.lib` holds VideoTerm-aware versions of the
stock conio modules (`libsrc/vt/`), linked with its selector ahead of
`a2lib-dos33.lib` (section 2). It is the link-time choice of section 3.1:
programs that don't want the backend link `a2lib-dos33.lib` alone and
pay nothing. Each replaced module is a
modified copy of stock cc65's that first tests `vt_active` (set at
startup when the card is found) and either drives the card or runs the
stock 40-column code. The stock `chline`, `cvline`, `cclear` and `cputs`
work unchanged on top, because they reach the screen only through
`cputc.s`'s entry points (`cputdirect`, `putchar`, `newline`) and
`gotoxy`.

| Module | On the VideoTerm |
|---|---|
| `vt.s` (new) | Detection, INIT, the WRITE wrapper, GOTOXY, cursor control, exit restore |
| `cputc.s` | `cputc`: `'\r'` is CR only, `'\n'` a line feed in the same column; `cputdirect`, `putchar`, `putchardirect`, `newline` |
| `gotoxy.s`, `gotoy.s` | Firmware GOTOXY (`$1E`, column + 32, row + 32) |
| `wherex.s`, `wherey.s` | The firmware's cursor variables (`$57B`, `$5FB`) |
| `clrscr.s` | Firmware clear-and-home (`$0C`) |
| `_scrsize.s` | 80 × 24 |
| `cpeekc.s` | Reads VRAM at the cursor, locating it as the firmware's `$CA59` does |
| `cgetc.s`, `rdkey.s` | Show the card's cursor while waiting for a key |
| `cout.s` | Calls WRITE directly; linking it (all console output does) links `vt.s`, so stdio-only programs get the backend too |

**Firmware facts the design relies on** (verified from the 2.4 ROM, by
disassembly):

- The Pascal 1.1 entries are INIT `$C311` (`JMP $C800`) and WRITE `$C31C`
  (`JSR $C9A7`). WRITE, unlike the BASIC entry, doesn't deselect other
  cards' `$C800` ROMs, so `vt_write` touches `$CFFF` first. It passes
  X = `$C3`, Y = `$30` per the protocol and preserves A, X and Y, so the
  same routine serves as the COUT hook.
- A plain `$0D` is a carriage return only; `$8D` goes through the control
  table as CR + LF; a line feed keeps the column. So conio's `'\r'` and
  `'\n'` map directly, and stdio's console output (which sends `$8D`)
  gets CR + LF.
- WRITE clears bit 7 of `$0478`, selecting **delayed wrap**: after a
  character in column 79 the cursor waits at column 80 until the next
  character. `wherex` reports 79 while a wrap is pending, and `putchar`'s
  backspace undoes it.
- After each character the firmware sets the CRTC cursor position
  (R14/R15) but never R10 (cursor start and mode), so the backend can
  hide or show the cursor through R10 without the firmware undoing it.
- INIT does a full setup only if the power-on marker at `$077B` isn't
  set; `vt.s` clears it first, so every program starts from a known
  state (standard character set, 24 lines, cleared screen).

**Single cursor.** Conio and stdio both write through the firmware, so
they share its cursor: `printf` output lands where `gotoxy` put the
cursor, as on the 40-column screen (checked by the tests). `CSW` is also
hooked, so code that calls `$FDED` directly reaches the card.

**Cursor visibility.** Hidden (R10 = `$20`), as on the stock 40-column
screen, and shown blinking (R10 = `$E0`, the firmware's own setting)
only while `cgetc` with `cursor(1)`, or stdio input, waits for a key.

**Controls in `cputc`.** Characters below `$20` other than `'\r'` and
`'\n'` show as their letters (`@`, `A`–`Z`, `[ \ ] ^ _`), as screen
codes `$80`–`$9F` do on the 40-column screen; they aren't sent as
firmware commands.

**Scrolling (difference from the 40-column screen).** A line feed on the
last row scrolls the card's screen, as the firmware does. The stock
40-column conio wraps the cursor to the top row instead. Each backend
keeps its native behavior.

**`revers` (decision).** `revers()` keeps its stock bookkeeping (it
returns the previous state) but has **no visible effect on the
VideoTerm**. The card can show inverse video only with an inverse
character ROM in the alternate-set socket or the inverse-video
modification; on a stock card, characters in the alternate set display
garbage. Selecting the alternate set for `revers` could be added later as
an opt-in for cards that have the ROM.

**Installing the output routine under DOS 3.3 (revised after a test).**
DOS 3.3 keeps its video intercept (`$9EBD`) in `CSW` and the true output
routine at `$AA53`, and on every character through its intercepts
copies the true handlers into the hooks and reinstalls its intercepts
(the mechanism in 6.3). The backends first stored their routines in
`CSW` directly, so the first stdio input dropped them. `test/cswtest.c`
confirmed it on the VideoTerm: `CSW` held the backend's routine at the
start and DOS's intercept after input, with DOS's saved hook still the
ROM's `COUT1` (`$FDF0`), and a character written through the monitor's
`COUT` (`$FDED`) after input never reached the card. cc65's own output
was unaffected, since `cout.s` calls the backend directly rather than
through `CSW`. Now, when DOS's intercept is in `CSW` (`CSW` equals the
address DOS keeps at `$9D04`), `vt.s` and `win.s` install their routines
as DOS's true output routine at `$AA53`, and DOS calls them; otherwise
they go into `CSW` directly. Exit restores whichever hook was changed.
Since 10.35 one copy of this code serves both, in `vt.s` (`a2_savehooks`,
`a2_hookout`, `a2_unhookout`), which `s80.s` calls: only one backend is
in use, so they share the saved hooks too.

**Exit.** `vtdone` restores `CSW`. If DOS's reconnect routine (`A851`)
moved the backend's hook into its saved true hook (`$AA53`) while the
program ran, it restores that too; otherwise BASIC's output would go to
freed memory after exit. The display returns to 40 columns (`$C058`),
unless output was already going to the card before the program started
(`CSW`, or DOS's saved hook, pointing into `$C3xx`, as after `PR#3`); then
it stays in 80 columns with the blinking cursor restored.

**Startup state in DATA.** Everything `vt.s`'s constructor sets is in
DATA, because `crt0` clears BSS after the constructors run (6.1).

**Size.** At most 427 bytes of resident code and data when every conio
function is used (757 against stock's 330), plus 118 bytes of startup
code that is freed after initialization. Programs link only the modules
they use.

### 3.6 40-column window implementation (increment 6; removed in 10.36)

*The window was removed in 10.36. This section stays because the 80 ×
24 model (`libsrc/s80`), Soft-70 (3.8) and the position gauge (6.3)
were built on it.*

**Packaging.** `lib/a2lib-c40win.lib` holds the VideoTerm backend
with the 40-column window (`c40win`) as its fallback, in place of the
stock 40-column screen (section 3.1: a binary contains the VideoTerm
backend plus one fallback). It holds `vt.s`, shared unchanged with
`a2lib-vt.lib`, the timer modules the gauge uses, and the window's conio
modules
(`libsrc/win/`), each with the same VideoTerm branch as in the VideoTerm
library and window code in place of the stock 40-column code.

**The same screen as the VideoTerm (decision).** A program sees 80 × 24
either way (`screensize` reports 80 × 24), and the window copies the
VideoTerm's behavior: delayed wrap at column 80, `'\r'` to column 0, a
line feed in the same column, scrolling at the bottom, and the
firmware's backspace (from column 0 to column 79 of the row above). So a
program behaves the same with or without the card. Two differences
remain, both from the hardware: the window shows `revers` (the text
screen has inverse video), and it can't show lowercase (a II+ limit;
`uppercasemask` applies, as on the stock screen).

**The 80 × 24 buffer.** 1,920 bytes in BSS. `crt0` clears BSS after the
constructors run (6.1), so the buffer can't be initialized by a
constructor; each byte holds its screen code XOR `$A0`, so the zeroed
buffer is already a blank screen.

**Panning (decision, from 3.2).**

- The window shows columns `left` to `left + 39`, with `left` at 0, 20
  or 40. By default it **follows the cursor in steps of 20**: when the
  cursor's column is outside the window, it moves to the nearest step
  that shows it. Half-window steps keep redraws rare while text is
  written across a line; each redraw copies 960 bytes.
- It pans **only when a character is written or the cursor is about to
  be shown** (`cgetc` with the cursor on, stdio input), never on a bare
  `gotoxy`, so a program drawing a screen doesn't trigger a redraw for
  every move.
- Programs control it through `include/c40win.h`: `c40_pan(left)` shows
  the given columns and stops following, `c40_follow()` resumes
  following, and `c40_left()` and `c40_active()` report the state. On the
  VideoTerm they do nothing (or return 0), so programs need no
  conditionals. Key bindings are left to programs, as decided in 3.2.

**Console output and input.** `cout.s` and the `CSW` hook send stdio
into the window: Return is CR + LF, line feed and backspace act as on
the card, other controls are ignored, and `INVFLG` applies, as in the
monitor's COUT. Before stdio input, `rdkey.s` pans to the cursor and
points the monitor's cursor (`CH`, `CV`, `BASL`) at it, so RDKEY's own
flashing cursor appears in the right place; its echo goes through COUT
into the window. `cgetc` shows the stock II+ caret (a flashing blank).

**Zero page.** `chline` keeps its counters in `tmp1`/`tmp2` across
`cputdirect`, and `cputs` keeps its string in `ptr1`, so the window code
uses only the monitor's `BASL`/`BAS2L` (`$28`–`$2B`) as pointers, set on
every use, the way stock `putchar` uses `BASL`.

**Startup and exit.** `win.s`'s constructor runs after `vt.s`'s
(priority 6 against 7; ld65 orders constructors by decreasing priority)
and does nothing if the card is in use. Otherwise it clears the screen
and hooks `CSW`; at exit it restores the hooks, as `vt.s` does, and
leaves the monitor's cursor at the window's, so BASIC continues below
the program's output.

**Size.** `win.o` is 663 bytes of code and tables, plus the 1,920-byte
buffer in BSS (no file space); the window's conio modules add a little
on top.

**Shared model (increment 9).** The window's 80 × 24 model moved to
`libsrc/s80/`, shared with Soft-70 (3.8, "Implementation"); `win.s` is
now the window's display. The window's behavior is unchanged (verified,
10.12); the resident size grew by 29 bytes (870 against 841: calls
through the display routines, and a general panning step).

### 3.7 Reflow filter implementation (increment 8)

**Hook (decision).** All stdio console output passes through `COUT` in
the library's `cout.s`: `write.s` sends each character there, and
`read.s` sends its echo of typed input. In every library, `COUT` is now
a 3-byte `JMP` in DATA whose target is the output routine itself
(`a2_rawcout`); `reflow_on` repoints it at the filter and `reflow_off`
restores it. Programs that never call `reflow_on` pay those 3 bytes and
3 cycles per character, and don't link the filter (every test program
grew by exactly 3 bytes). `CSW` was rejected as the hook: DOS 3.3
manages it (3.5), and the VideoTerm and window libraries' stdio output
doesn't go through it.

**What the filter must preserve (verified in cc65's source).** `write.s`
relies on `COUT` preserving X and Y (its comment says so), and `read.s`
uses A after echoing through `COUT`; `write.s` keeps its buffer pointer
and count in the zero page. The filter therefore preserves A, X and Y
and uses no zero page.

**Nothing held back (decision).** A buffering word-wrapper holds each
word until the next space, so a prompt such as `Name?` would stay
invisible while the program waits for input. The filter instead prints
each character at once and keeps the current word (up to 80 characters,
in BSS). When a word would overflow the line, it backs up over the
word with backspaces, blanks it, breaks the line, and prints the word
again. A word that fills a whole line is broken there.

**Line length: width - 1 (decision).** The backends wrap differently at
the right edge: the stock screen wraps immediately after the last
column, the VideoTerm and the window on the next character. A line that
exactly filled the width would therefore be followed by a blank line on
one backend but not the others when the text's own line break came
next. Holding lines to width - 1 characters means the filter never
relies on the display's wrap, so output looks the same on every
backend, at the cost of one column.

**Spaces.** A space that ends a full line becomes the line break.
Spaces at the start of a line the filter began are dropped; spaces
after the text's own line break are kept, so indentation survives.
Other control characters pass through; backspace moves the filter's
column back one.

**Width.** `reflow_on(width)` takes 2-81 (values outside are clamped);
0 means the visible width, from a small per-library module
`viewport.s` (`a2_viewport`): the monitor's window width (40) in the
base library; 80 on the VideoTerm; in the window library, 40 (the
visible columns, as decided in 3.2) or 80 on the VideoTerm.

**Column tracking.** The filter counts columns itself, starting from
`wherex` at `reflow_on`. After moving the cursor with conio, a program
calls `reflow_on` again. Typed input echoed by stdio passes through the
filter too.

**Size.** `reflow.s` is 304 bytes resident plus 87 bytes of BSS (the
estimate before implementation, 150-250 bytes plus an 80-byte buffer,
was low); `viewport.s` 3 to 10 bytes; the `COUT` vector 3 bytes.

**Testing.** `test/sim/reflowsim.c` (`make simtest`) links the real
`reflow.s` with stubs that record what it sends to the screen, renders
that onto a model screen, and compares against wrapping worked out by
hand: greedy wrapping, moved and broken words, dropped and kept spaces,
the starting column, backspace, the viewport default (40 and 80),
`reflow_off`, and register preservation. `test/reflowtest.c`, built for
all three libraries, prints through the filter on the Apple II and reads
the screen back with `cpeekc`.

### 3.8 Soft-70: research, design and implementation (increment 9)

**Precedent.** Software 70-column displays existed in the period; 70
columns is what hi-res allows with 4-pixel cells (280 / 4 = 70).

- **Soft Seventy** (verified from a disk image of the original
  distribution): its `FONT MERGE` program reads "COPYRIGHT 1981
  HEARTWOOD DESIGNS, INC". It gave a 70-column screen with a full
  96-character upper- and lowercase set and a separate graphics set,
  worked with programs using the standard I/O hooks, and loaded its
  regular font at `$D00` and its graphics font at `$1000`.
- **Flex Type** (verified from its manual): Mark S. Simonsen, Beagle
  Bros, 1982. 70, 56 and 40 columns, plus a 20-column double-wide mode;
  up to nine resident character sets of 768 bytes each; 70-column fonts
  use "the leftmost 4 pixels" of each row and carry a `.70` suffix; it
  accepts character sets from Apple's DOS Tool Kit "and other similar
  hi-res character programs"; it includes a character editor (A.C.E.);
  and its manual states that 70-column text "requires monochrome
  monitor".
- Reported but not verified here: Magic Window II, Word Handler and
  ScreenWriter II also used hi-res 70-column text.

**The period font format (verified from Soft Seventy's font files).**
A character set is **768 bytes: 96 characters (`$20`-`$7F`) x 8 bytes**,
one byte per scanline, top first, the same layout as DOS Tool Kit and
Flex Type sets. In each byte, **bit 0 is the leftmost pixel** (the
standard hi-res order, so no bit reversal is needed), and a 70-column
glyph uses bits 0-3. In `ASCII.FONT`, every printable glyph sits in
pixels 1-3, with pixel 0 as the gap between characters; only `DEL`
(`$7F`, a solid block) uses a fifth pixel. **Descenders use the bottom
scanline** (row 7: `Q _ g j p q y`). Because 70-column glyphs use only 4
bits, Soft Seventy also stores **two fonts in one 768-byte file**:
`SYSTEM.FONT` is exactly `ASCII.FONT` in the low nibble of each byte and
`GRAPHICS.FONT` in the high nibble (checked byte for byte).

**Licensing.** Both products are commercial: Soft Seventy is copyright
Heartwood Designs, and Flex Type's manual licenses it "only for your
personal use" and forbids reproduction without permission. a2lib
therefore can't ship their fonts. Proposed instead: Soft-70 uses the
768-byte period format, ships its own license-clean default font, and
can load a font file at run time, so period `.70` fonts a user owns
(and fonts edited with A.C.E.) work without a2lib distributing them;
merged two-font files could supply the alternate character set.

**Geometry (computed).** Hi-res rows are 40 bytes of 7 pixels, bit 0
leftmost; bit 7 of each byte shifts that byte's pixels by half a pixel
(selecting the blue/orange colour set). A 4-pixel cell at column c
starts at pixel 4c: byte 4c / 7, bit 4c mod 7. The pattern repeats
every 7 cells (28 pixels, 4 bytes); cells at c mod 7 = 1, 3, 5 straddle
two bytes. Scanline k (0-7) of text row r is at
`$2000 + (r & 7) * $80 + (r >> 3) * $28 + k * $400`, so a cell's 8
scanlines differ only by `$04` in the high byte: a 24-entry table of row
bases suffices. No row's 40-byte run crosses a page, so copies pay no
page-crossing cycles.

**Drawing (proposed).** Glyph rows are 4 bits wide. For each of the 7
bit offsets, a 16-entry table gives a glyph row's contribution to the
first byte and, for offsets 4-6, the second (7 x 16 x 2 = 224 bytes), so
a scanline is a table lookup, a mask and an OR per byte, with no
shifting at run time. Estimated **about 377 cycles per character
(roughly 2,700 characters per second)**, using self-modified absolute
addresses rather than zero page (conio callers keep `ptr1`, `tmp1` and
`tmp2` across `cputdirect`, as with the window, 3.6). With the period
format, each scanline's 4 bits are read directly (the low nibble, or
the high nibble of a merged file), with no unpacking.

**The 80 x 24 screen.** As with the 40-column window, a program sees 80
x 24 (the shadow buffer is shared code, 3.1); Soft-70 shows 70 of the 80
columns, so it pans between two positions (columns 0-69 and 10-79). A
pan can't shift pixels, since 10 columns are 40 pixels, not a whole
number of bytes, so it redraws from the buffer: about 0.6 s for a full
screen, or about 0.3 s if the screen is cleared first and blank cells
skipped (at 40% full). Pans are rare. Reflow's viewport width would be
70 (lines of 69 characters, 3.7). The position indicator is the XOR
scanline bar decided in 6.3.

**Scrolling (computed).** Scrolling up one text row moves 23 x 8
scanlines of 40 bytes (7,360 bytes) and clears one text row:

| Method | Cycles | Time |
|---|---|---|
| Simple loop per byte | 107,480 | 105 ms |
| Unrolled per scanline (`LDA abs,Y` / `STA abs,Y` x 40, ~240 bytes of code) | 72,520 | 71 ms |
| Unrolled, copying only each row's used length (lines 50-70% full) | ~37,000-51,000 | 36-50 ms |

Proposed: unrolled copy with per-row length tracking (the longest
visible extent of each text row, 24 bytes, taken from the buffer).
Throughput with 80-character lines, drawing plus one scroll per line
(about 101 ms without length tracking):

| Line rate | A line every | Keeps up |
|---|---|---|
| 300-2,400 baud | 2,667-333 ms | Yes |
| 9,600 baud | 83 ms | Slightly behind |

Falling behind costs nothing over the Uthernet II: TCP flow control
holds data back instead of losing it, so a burst only displays a little
slower. (Over a serial line without flow control it would lose data.) A
possible later refinement is batch scrolling: moving the screen by
several rows at once costs about the same as one, when more output is
already waiting.

**Artifact colour (researched).**

- Hi-res colour comes only from the composite signal's interpretation
  of the bit pattern: alternating lit and unlit pixels show colour, two
  or more adjacent lit pixels show white. An isolated lit pixel is
  violet or green (bit 7 clear) or blue or orange (bit 7 set) by its
  column's parity.
- The II+ colour killer (Revision 1 boards on) **removes the colour
  burst only in text mode**, and imperfectly; in graphics modes,
  including Soft-70's full-screen hi-res, the burst is always on. So on
  a colour monitor Soft-70 text fringes on a real II+ as well. Period
  users of hi-res text used monochrome monitors, or added a switch to
  cut the burst.
- Because the cell width is even, a glyph pixel's parity depends only
  on its column within the cell: each stroke has the same colour wherever
  the character appears (with bit 7 clear, glyph columns 0 and 2 violet,
  column 1 green; adjacent lit pixels white). Fringing is therefore
  consistent rather than flickering from position to position.
- Options: (a) a thin font designed for monochrome monitors, accepting
  consistent fringes in colour; (b) "bold stems" (2-pixel verticals,
  which show white) for colour monitors, at a cost in legibility in a
  3-pixel-wide glyph. Proposed: (a), with bit 7 clear throughout.
- On a colour monitor, the gauge's dotted track (alternating pixels)
  shows as a solid coloured line and its thumb as white.

**Font (researched).** The period fonts use glyphs 3 pixels wide (pixels
1-3) and up to 8 tall, with descenders on the bottom scanline. That
scanline is where the gauge's XOR bar goes (6.3), so on row 23 the bar
overlaps descenders for the second it is shown; XOR leaves them intact
when the bar is removed, and only row 23 is affected. Robey
Pointer's "Tom Thumb" font (4 x 6 cell, 3 x 5 usable pixels, upper and
lowercase, derived from Brian Swetland's font) may be used under MIT,
CC0 or CC-BY 3.0; CC0 is compatible with a2lib's zlib license. Options:
use Tom Thumb's glyphs within the taller cell, or draw taller 3 x 7
glyphs (more legible, more work), possibly starting from Tom Thumb.

**Memory (estimated).** Font 768 bytes (period format), shift tables 224, row
tables 48, code about 1 KB including the unrolled scroll, plus the
shared 1,920-byte buffer (BSS) and the reserved hi-res page
(`$2000`-`$3FFF`, 8 KB), which is why Soft-70 is a link-time choice
(3.1). Measured figures are under "Implementation" below.

**Testing support in ReplicApple2Plus (done).** A selectable
**monochrome monitor** setting (white, green or amber phosphor),
persisted with `java.util.prefs` as `ShiftKeyModSetting` is: in
monochrome, `HiResRenderer` draws every lit bit in the phosphor colour
instead of applying its artifact-colour rules; lo-res would show each
colour's bit pattern as a stipple, as a real monochrome monitor does.
This models what period users did, rather than the II+ colour killer,
which acts only in text mode. Refinement: a monochrome monitor also
shows bit 7's half-pixel shift as a real offset, which needs 560-pixel
rendering. This is a change to ReplicApple2Plus, not to a2lib; it was
made before increment 9, half-pixel shift included.

**Decisions (confirmed):**

1. **Font format:** the 768-byte period format (96 characters x 8
   bytes, bit 0 leftmost, bits 0-3 used), so period fonts a user owns
   can be loaded at run time; merged two-font files supply the alternate
   character set.
2. **Default font:** a2lib's own, glyphs 3 pixels wide and up to 8 tall
   like the period fonts, possibly starting from Tom Thumb (CC0).
3. **Glyph style:** thin, designed for monochrome monitors, with bit 7
   clear; fringes on colour monitors are accepted.
4. **Lowercase:** yes, with descenders on the bottom scanline as in the
   period fonts.
5. **Scrolling:** unrolled copy with per-row length tracking.
6. **Order:** the monochrome monitor setting in ReplicApple2Plus comes
   first, so Soft-70 can be judged the way period users saw it.

**Implementation decisions (confirmed, increment 9):**

1. **Memory layout:** the program starts at `$4000`, above the hi-res
   page, and the buffer and font go in `LOWBSS` below it, so the program
   file isn't padded. cc65's stock `apple2-hgr.cfg` was the alternative;
   it places an `HGR` segment at `$2000` in the file, making every
   Soft-70 binary at least 14 KB, mostly zeros, slow to BLOAD under DOS
   3.3. In implementation, cc65's stock `apple2.cfg` already provides this
   layout with `--start-addr 0x4000` (its `LOW` area runs from `$0800` to
   the start address and holds `LOWBSS`), so no linker config of a2lib's
   own is needed. Link-time assertions in `s70.s` catch a program linked
   without it, or `LOWBSS` reaching `$2000`.
2. **Sharing:** the 80 × 24 model is extracted from the window into
   `libsrc/s80/`, with the window and Soft-70 as displays, rather than
   copied; the window was verified unchanged before Soft-70 was built on
   it (10.12).
3. **Cursor:** an inverse block, blinking at about 2 Hz (250 ms per
   phase) from a periodic timer; steady if no timer slot is free.
4. **Fonts:** the default font is compiled in; `s70_font(set, nibble)`
   replaces it with one nibble of a 768-byte set read by the program, so
   merged period files work. Selecting the second set of a merged file
   while text is shown has no counterpart in the other backends and is
   left for later. The default font is drawn new, 3 x 7 with descenders,
   not derived from Tom Thumb, and reviewed as a rendered preview.

**Implementation.**

- **Files.** `libsrc/s80/` holds the model (`s80.s`) and the conio
  modules the window and Soft-70 share (`cputc`, `cpeekc`, `gotoxy`,
  `gotoy`, `wherex`, `wherey`, `clrscr`, `cout`, `_scrsize`,
  `viewport`). Each is assembled once per backend, with the backend's
  directory first on the include path for its `display.inc`: the visible
  width and panning step (40/20, 70/10), the prefix of the C interface
  (`c40_`, `s70_`), the buffer's segment (`BSS`, `LOWBSS`; since 10.36
  always `LOWBSS`, not a parameter), and two macros for screen codes. The model calls the display through eight
  routines (`disp_init`, `disp_done`, `disp_cell`, `disp_redraw`,
  `disp_scroll`, `disp_clear`, `disp_gauge_draw`, `disp_gauge_erase`;
  `s80.inc`). `libsrc/win/win.s` was the window's display (until 10.36),
  and
  `libsrc/s70/` holds Soft-70's display (`s70.s`), `cgetc`, `rdkey` and
  the generated default font (`font.s`, from `tools/s70font.txt` by
  `tools/s70font.py`, which also writes a `.70` file or a preview).
- **Screen codes.** In the window, codes are the text screen's, so
  inverse letters lose their case. Soft-70 uses bit 7 for normal (set)
  or inverse (clear) and keeps the character in bits 0-6, so inverse
  lowercase and punctuation show correctly; flashing shows as inverse.
  `uppercasemask` is set to `$FF` (lowercase shown), as on the
  VideoTerm. `cpeekc` returns the character in either video.
- **Drawing.** A cell's glyph index selects one of the font's three
  pages and an offset in it, the column a byte and bit offset (70-entry
  tables), the row a base address (24-entry tables). The two loops (one
  byte per scanline for offsets 0-3, two for 4-6) use self-modified
  operands for the font page, inverse mask, lookup table, byte and mask,
  and `BAS2L` as the pointer, advancing `$400` per scanline. Every byte
  written has bit 7 clear.
- **Scrolling.** `sext[r]` records one more than the rightmost byte drawn
  on screen row `r` since it was cleared; a row copies the larger of its
  own and the next row's extent, 8 scanlines per byte column, with
  self-modified addresses set per row. Blank cells are never drawn, so
  the space glyph is kept blank (`s70_font` clears it).
- **Panning** clears the page and draws the window's nonblank cells.
- **Gauge.** The bar is drawn and removed with EOR on row 23's bottom
  scanline. Drawing a cell on row 23 while it is shown puts the bar back
  into that cell's bits; scrolling takes it off and puts it back; panning
  and clearing remove it with the page.
- **Cursor.** The cell is redrawn from the buffer, inverted or not, at
  each blink and when it is removed, so output from a timer callback in
  that cell isn't lost. `rdkey` shows it, then calls the monitor's RDKEY
  through the input hook with the monitor's own cursor at row 0, column
  0 of the hidden text screen, as stdio input and DOS expect.
- **Startup and exit.** The constructor copies the font, sets
  `uppercasemask`, clears the page and switches to full-screen hi-res
  page 1; the model then clears and hooks `CSW` as in the window. At
  exit, text mode and `HOME`.

**Measured (sim65, `make simtest`).** The estimates above were low:

| Operation | Estimated | Measured |
|---|---|---|
| `disp_cell`, one cell | about 377 cycles | about 650 (offsets 0-3) to 880 (4-6) |
| `cputc`, model included | | about 1,010 cycles: about 1,000 characters/s |
| Scroll, 70 columns in every row | 71 ms | 108,000 cycles: 106 ms |
| Scroll, 38 columns in every row | 36-50 ms | 78,000 cycles: 76 ms |
| Pan, 69 columns in every row | 0.6 s | 909,000 cycles: 0.89 s |

The estimate counted a tighter inner loop than the per-scanline
bookkeeping allows (pointer advance, two table lookups, masked stores),
and the scroll figures include the model's own buffer scroll (about
29,000 cycles, shared with the window). At about 1,000 characters per
second, Soft-70 keeps up with 9,600 baud text without scrolling and with
2,400 baud with a scroll per line; over the Uthernet II, TCP flow control
absorbs the rest.

These figures vary with where the linker places Soft-70's code (10.35,
10.36): an inner loop's backward branch costs a cycle more each time
it's taken when it crosses a page, and where `s70.s` lands depends on
everything linked before it, so each program differs. Measured over 64
placements (`s70sim` with 0-252 bytes ahead of the library): `cputc`
1,012-1,018 cycles (0.6%), the 70-column scroll 108,478-111,191
(2.5%), the 38-column scroll 77,606-79,928 (3.0%), the pan
904,402-911,377 (0.8%).
With cc65's `apple2.cfg`, whose segments have no alignment, a module
can't align its loops without ld65 warning that the program might not
work. For the same reason the font in LOWBSS isn't page-aligned: at its
address in the tests, `$0F90`, the glyph loads cross a page on all 8
scanlines for 18 of every 32 glyphs, about 4.5 cycles a character on
average. A linker configuration of a2lib's own could align both.

Possible later speedups, if needed: a font transposed
into 8 planes with an unrolled scanline loop (about 40% less per cell,
about 300 bytes more code), and batch scrolling.

**Memory (measured).** Resident: model 656 bytes, display 1,476, `cgetc`
61, `rdkey` 52, about 2.2 KB in all. Below the program, in `LOWBSS`: the
buffer (1,920), the font (768), row extents and the gauge's bar (64). The
default font (768) and the startup code are in `ONCE`, reused as BSS
after startup.

### 3.9 Text marker: copying Soft-70's text (increment 9)

**Problem.** An emulator's text copy reads the text page (`$400`-`$7FF`),
where text-mode characters live. While Soft-70 is shown, the text page
holds nothing: the text exists only in a2lib's 80 × 24 buffer, at an
address the linker picks, in a2lib's own encoding. Recognising characters
from the hi-res image was considered and rejected as too complicated
(decision). Reading the buffer is memory inspection, as the standard copy
already does; what's needed is a way to find it without knowing a2lib's
link map.

**Decision: a marker directly before the buffer.** Soft-70's constructor
writes 16 bytes immediately before the buffer; the destructor clears the
first byte at exit. A tool (ReplicApple2Plus's Copy) searches `$0800`-
`$1FFF` for the signature while hi-res is shown and, if it finds one,
copies the whole 80 × 24 screen, including the columns panned out of view.
The format is documented here, so any program can use it.

| Offset | Bytes | Contents |
|---|---|---|
| 0 | 7 | Signature: ASCII `A2SCR80`, bit 7 clear |
| 7 | 1 | Version: 1 |
| 8 | 1 | Columns (80) |
| 9 | 1 | Rows (24) |
| 10 | 1 | Visible columns (70) |
| 11 | 1 | Encoding (below) |
| 12 | 2 | Address of the leftmost visible column (one byte), low byte first |
| 14 | 2 | Address of the buffer, low byte first (offset 16, directly after) |

**Encoding 1 (Soft-70).** The buffer holds rows of 80 bytes, top first.
Each byte XOR `$A0` is a screen code: bit 7 set for normal video, clear
for inverse; bits 0-6 the character, with `$00`-`$1F` standing for
controls shown as their letters (`$40`-`$5F`). So a blank screen is all
zeros. Encoding 0 (the text screen's own codes) was reserved for the
40-column window (removed in 10.36), which wrote no marker: its buffer
was in BSS, which the constructor must not write (10.12), and the text
page already showed its visible 40 columns.

**Encoding 2 (plain ASCII).** Each byte is the character itself,
`$20`-`$7E`, in normal video; a blank is `$20`. Readers show anything
else as a blank. This is how Uthernet2's TELNET and GOPHER keep their
80 × 24 screen (github.com/sbabcoc/Uthernet2, `src/apple`), which they
draw with Soft-70's techniques and font: the marker at `$0800`, the buffer
at `$0810`, written only while Soft-70 is in use, as here.

Readers check the encoding: a marker in an encoding they don't know is
ignored, as one of another version is, rather than decoded as encoding 1.
ReplicApple2Plus reads encodings 1 and 2 (in releases after 1.9.0; 1.9.0
decodes every marker as encoding 1).

**Limits.** A program that stops without running its destructors (a crash,
RESET) leaves the marker in memory; a later hi-res program could then be
mistaken for Soft-70 text. The VideoTerm build writes no marker when the
card is in use, since the card holds the text.

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
fallback.** Features are ported one by one instead of emulating an
entire OS interface.

**Functions with no DOS 3.3 equivalent fail at link time (revised in
10.26).** A failure that can be caught at link time isn't left to run
time. Each stock module whose C functions still depend on ProDOS is
replaced by a guard of the same name (`libsrc/guard`), which defines the
function as an alias of an undefined symbol that names it:
`dio_open_has_no_DOS_3_3_implementation`, for example. ld65 reports that
symbol, and the guard's file and line, for a program that calls it.
Programs that don't call one link no guard. Guarded: `getcurrentdevice`,
`getdevicedir`, `getfirstdevice`, `getnextdevice`, the `dio_*` calls,
`file_set_type`, `file_set_auxtype`, `statvfs`, `mkdir`, `rmdir`,
`clock_getres` and `dir_entry_count` (which reads cc65's ProDOS `DIR`).
`opendir`, `readdir`, `closedir` and `rewinddir` have guards under their
stock names too, for programs compiled without a2lib's `dirent.h`
(section 2). `make linktest` checks every one of them.
`clock_gettime` and `clock_settime` have a DOS 3.3 version, the software
clock, but in `a2lib-timer.lib` (section 2): their guards' symbols say
so, `clock_gettime_needs_a2lib_timer`, and the timer library, linked
ahead of the core, supplies the functions instead.
Deleting the stock modules instead wouldn't work: `cl65` appends cc65's
own `apple2.lib`, which would supply them again (confirmed with a link
map).

| Replace | Keep |
|---|---|
| `open.s` (incl. `closedirect`, `freebuffer`), `rwcommon.s`, `lseek.s`, `sysremove.s`, `sysrename.s`, `stat.s`, `opendir`/`readdir`/`closedir`/`rewinddir` | `filedes.s`, `close.s`, `read.s`, `mli.s`, console device paths |

- `fdtab` works unchanged: a nonzero `REF_NUM` below `$80` indexes the
  layer's own File Manager control blocks.
- **`write.s`:** shared code except the `O_APPEND` path, which calls
  `GET_EOF`/`SET_MARK` directly. Instead of maintaining a fork, propose
  an upstream patch that moves "seek to end" into a helper next to
  `rwcommon`. Then `write.s` no longer depends on the OS, and the DOS 3.3
  build replaces only the helper. a2lib does this itself (10.24): its
  file code, `rwfile.s`, moves to the end, and its `write.s` is stock's
  without the `O_APPEND` path.

### 4.3 `struct dirent`

The DOS 3.3 build has its own layout (`include/dirent.h`; section 5.9
gives the fields). This is the one public-header change (see section 2).
It's the change most likely to need discussion upstream; it goes to the
cc65 maintainers together with working code (section 9).

**Revised in increment 3, and back in increment 13:** the first draft had
`d_type` hold the DOS file type. Increment 3 changed it to the
ProDOS-equivalent type, following the guiding principle as it then was,
with the DOS type in a separate `d_dostype` field. Under the revised
principle, `d_type` holds DOS 3.3's own type again, and `d_dostype`, now
the same value, is gone.

### 4.4 File Manager facts (verified, *Beneath Apple DOS* ch. 5–6)

- Entry: `JSR $3DC` returns the parameter list address (Y=low, A=high);
  `JSR $3D6` calls the File Manager. X=0 on OPEN creates the file if it's
  missing; X≠0 does not.
- **Buffers are supplied by the caller on every call:** a 45-byte work
  area, a 256-byte track/sector list buffer, and a 256-byte data buffer,
  557 bytes per open file. **Decision (10.23):** use DOS's own file
  buffers (ch. 6, DOS BUFFERS), MAXFILES of them between HIMEM and DOS,
  chained from `$9D00`. Each holds the three buffers, a 30-byte name field
  and DOS's pointers; a buffer is in use while the name field's first byte
  is nonzero, the convention DOS's commands follow (ch. 8, `$A764`,
  `$A2FC`). `fmbuf.s` reserves a free one with `$FF` there and keeps the
  library's per-file fields (11 bytes) in the rest of the name field, so
  file I/O needs no `malloc` and no memory of its own. At most MAXFILES
  files are open at once (3 by default; `MAXFILES` before the program
  raises it, up to the 5 fdtab has room for); one more fails with NO
  BUFFERS AVAILABLE (`ENOMEM`), as DOS itself does. `remove`, `rename` and
  `exec` need a free buffer too, as DOS's DELETE and RENAME do. Buffers
  are released on `close` and at exit, before `exec`'s command, which
  needs one. A DOS `CLOSE` command printed by the program closes the
  library's files too; programs shouldn't issue one with files open.
  Until 10.23, each control block was `malloc`'d (568 bytes), which
  pulled `malloc` and `free` (739 bytes) into every program that opened a
  file.
- A POSITION is required before the first READ or WRITE.
- A range WRITE takes the byte count **minus one**.
- RENAME takes the new name's address at bytes `02/03`.
- CATALOG only prints to the output device. **`readdir` reads the VTOC
  and catalog sectors directly through RWTS (`$3D9`).**
- Catalog entries store the type byte (bit 7 = locked), a 30-character
  name, and a length **in sectors only**. No byte length is stored.
- **File-type codes: one coding (corrected in increment 13).** OPEN
  stores the type it's given in a new file's directory entry, and copies
  the entry's type back to the parameter list, unchanged (ch. 8, `$ABA6`).
  CATALOG names `$08` S and `$10` R (its table at `$B3A7`), and so do the
  catalog entry layout (ch. 4). Ch. 6's parameter list table gives them
  the other way round (`$08`=R, `$10`=S); that table is wrong. This
  section first said the two codings differ, from ch. 6. So `FMT_RELOC`
  was `$08`, the code for S: `_filetype = PRODOS_T_REL` created S files,
  and `stat` reported S files as REL. No test created an R file until
  increment 13's, which caught it on the emulator: `stat` said R and
  `readdir` didn't.
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

**Decision (revised in increment 13):** `_filetype` takes **DOS 3.3's own
type codes**, as a catalog entry stores them and `CATALOG` lists them.
`include/dos33_filetype.h` names them, after cc65's `PRODOS_T_*` and
`CBM_T_*`:

| Constant | Type | Code | Created |
|---|---|---|---|
| `DOS33_T_TXT` | T | `$00` | yes |
| `DOS33_T_INT` | I | `$01` | yes |
| `DOS33_T_BAS` | A | `$02` | yes |
| `DOS33_T_BIN` | B | `$04` | yes (the default, as stock defaults to BIN) |
| `DOS33_T_S` | S | `$08` | yes |
| `DOS33_T_REL` | R | `$10` | yes |
| `DOS33_T_NEWA`, `DOS33_T_NEWB` | "new" A, B | `$20`, `$40` | no: `EINVAL` |

OPEN takes the same codes, so `open` passes `_filetype` through (4.4).
Nothing verified shows the File Manager creating the "new" A and B types,
so they fail with `EINVAL`, as any other code does. `stat` and `readdir`
report the same codes (5.8, 5.9). `_filetype` applies only to a file
`O_CREAT` creates: an existing file opens whatever it says, since
`O_CREAT` matters only when the file doesn't exist (POSIX; fixed in
10.30).

**Before increment 13**, `_filetype` took ProDOS's codes (`$04`→T,
`$06`→B, `$FC`→A, `$FA`→I, `$FE`→R), so source written for ProDOS would
create the same kinds of files. Under the revised guiding principle a
DOS 3.3 program uses DOS 3.3's codes. Note that ProDOS's TXT code, `$04`,
is DOS 3.3's B: code that still sets `PRODOS_T_TXT` now creates a B file.

Files of types other than T, A, I and B (R, S, and the "new" A and B
types) are transferred raw. They have no end recorded below sector
granularity, so reads return data up to the end of the last sector, and
`O_APPEND` fails with `EINVAL` instead of appending after padding.

### 5.5 Names and locations

ProDOS addresses files by pathname (`/VOLUME/NAME`). DOS 3.3 names carry
no location, but the File Manager needs slot and drive in every call.

**Decision (revised in increment 14): POSIX paths**, as Oliver Schmidt
proposed on cc65/cc65#3050: cc65 is about POSIX, and targets whose OS has
no paths still map their devices to them. A DOS 3.3 path names at most a
slot, a drive and a file:

| Path | Meaning |
|---|---|
| `"/6/2/NAME"` | slot 6 (1–7), drive 2 (1–2) |
| `"2/NAME"` | drive 2 in the current slot |
| `"NAME"`, `"./NAME"` | the current slot and drive |

- **The current directory is DOS's last-used slot and drive**, at `$AA6A`
  (slot) and `$AA68` (drive), 2 bytes each (*Beneath Apple DOS* ch. 8).
  `getcwd` gives `"/6/2"` (`initcwd.s`). `chdir` sets them
  (`syschdir.s`), so the setting stays after the program exits, as
  ProDOS's prefix does. A plain name works as it always has.
- **A path's own slot and drive don't change the current directory.**
  (The first version made an explicit `,S` or `,D` the new default, as DOS
  commands do.)
- **Directories,** for `opendir` and `chdir`: `"/6/2"`, `"2"`, `"."` and
  `""`, each optionally ending in `/`. `"/"` and `"/6"` aren't
  directories: they fail with `EINVAL`, as any malformed path does (cc65
  has no `ENOTDIR`). `chdir`, like DOS's own `,D2`, doesn't read the
  drive; the first file access on it does.
- **No volume number.** Paths match any volume, as a DOS command without
  `,V` does. The first version took `,V254`.
- **Names** start with a letter, so a leading digit is always a drive and
  never part of a name. They're up to 30 characters, and may hold any
  character but `/`, commas included. The File Manager takes any name;
  only DOS's command parser stops at a comma. `exec` therefore refuses a
  name with a comma (5.10). When no fdtab slot is free, `open` fails with
  `EMFILE`.
- **Case (decision):** names are converted to uppercase, so
  `open("hello")` finds `HELLO`, as names are case-insensitive under
  ProDOS.
- **Storage:** names are stored with the high bit set and padded with
  `$A0` to 30 bytes, the way DOS's own command parser fills its name
  buffer (*Beneath Apple DOS* ch. 8, `A095`).
- Any malformed path fails with SYNTAX ERROR (`EINVAL`).

**Before increment 14**, names took DOS's own suffixes,
`"MYFILE,S6,D2,V254"`, as typed at the DOS prompt, with `opendir(",D2")`
for directories. That followed the first guiding principle's "respecting
DOS 3.3 idioms"; the revised principle puts cc65's generic interface, and
so paths, first.

### 5.5a remove and rename

- `remove` uses the File Manager's DELETE. A locked file fails with
  `EACCES`, as under ProDOS; so does `rename` (RENAME's own error,
  through `fm_maperr`; fixed in 10.27).
- A file renamed to its own name is left as it is and `rename` returns 0
  (POSIX; fixed in 10.30). It must exist, and not be open, as for any
  rename.
- `rename` uses RENAME. Either path may give the slot and drive, but
  **the new one must be where the old one is**: DOS's RENAME can't move a
  file. Another slot or drive fails with `EINVAL` (cc65 has no `EXDEV`).
  (Before increment 14, the new name took no suffixes at all.)
- DOS's RENAME doesn't check whether the new name is already in use and
  would leave two files with the same name. **As under ProDOS, an
  existing new name fails with `EEXIST`**: `rename` first tries to OPEN
  the new name without allocating it.
- Both need the File Manager's work area and buffers even without an
  open file, so they reserve a DOS buffer for the call (4.4). If none is
  free, they return DOS's NO BUFFERS AVAILABLE (`$0C`), which maps to
  `ENOMEM` (5.6).
- **An open file can't be deleted or renamed** (library code `$11`,
  `EINVAL`, 5.6), as ProDOS refuses too. DOS 3.3 itself doesn't check. Before DELETE or RENAME, both
  OPEN the file in that buffer without allocating it,
  CLOSE it, and compare the work area's first T/S list (track, sector),
  slot and drive ("Beneath Apple DOS" ch. 6, work area offsets `$00`-`$01`,
  `$26`, `$27`) with those of every open file (`fm_isopen`, `fmbuf.s`).
  The first T/S list is unique on a disk, so a file is recognised under
  any name it's opened by. A file missing or locked fails as before. The
  check costs a catalog search, as DELETE and RENAME make anyway.
  **Limit:** the volume number isn't compared, since disks commonly share
  254; after swapping disks in a drive while a file is open, a file on the
  new disk whose first T/S list happens to be in the same place is
  refused too. Added in increment 10 (10.13).

### 5.6 Error mapping

**Decision (revised in increment 12):** `__oserror` holds **DOS 3.3's own
error numbers**, the ones `ONERR` reports, with DOS's messages from
`_stroserror`. a2lib has its own `oserror.s` (the number → `errno` table)
and `oserrlist.s` (the messages), which replace the stock ProDOS
modules. The File Manager's return codes are DOS's error numbers 1–10
already (*Beneath Apple DOS* ch. 6, ch. 8 `$A971`), so `fm_maperr` only
sends unknown codes to I/O ERROR. RWTS codes go to the numbers DOS itself
reports for them. The `errno` values programs see are unchanged from the
first version, which translated everything into ProDOS codes.

| `__oserror` | DOS 3.3 message | `errno` | Produced by |
|---|---|---|---|
| `$01` | LANGUAGE NOT AVAILABLE | `ENOSYS` | (File Manager; not produced) |
| `$02`, `$03` | RANGE ERROR | `EINVAL` | File Manager: bad call or sub-call |
| `$04` | WRITE PROTECTED | `EACCES` | File Manager; RWTS `$10` |
| `$05` | END OF DATA | (end of file, not an error) | File Manager, handled by `read` |
| `$06` | FILE NOT FOUND | `ENOENT` | File Manager |
| `$07` | VOLUME MISMATCH | `ENOENT` | File Manager; RWTS `$20` |
| `$08` | I/O ERROR | `EIO` | File Manager; other RWTS errors; unknown codes |
| `$09` | DISK FULL | `ENOSPC` | File Manager |
| `$0A` | FILE LOCKED | `EACCES` | File Manager |
| `$0B` | SYNTAX ERROR | `EINVAL` | A bad name (`fmname.s`, `rename`) |
| `$0C` | NO BUFFERS AVAILABLE | `ENOMEM` | Every DOS buffer in use (`open`, `remove`, `rename`, `exec`; 4.4) |
| `$0D` | FILE TYPE MISMATCH | `ENOEXEC` | `exec()` of a file that isn't B or A |
| `$0E`, `$0F` | PROGRAM TOO LARGE, NOT DIRECT COMMAND | `ENOMEM`, `EINVAL` | (DOS commands; not produced) |

**Library codes (decision).** Some failures have no DOS 3.3 number,
because DOS itself doesn't refuse them. DOS's RENAME, for instance,
accepts a name that already exists. `remove` and `rename` must still
return an OS code: cc65's `remove.s` and `rename.s` pass the
`__sysremove`/`__sysrename` result to `___mappederrno`. So these get
codes of the library's own, numbered after DOS's range and mapped in the
same table. That is the precedent of Atari's `oserror.s`, whose code 183
is "used by cc65 rtl". Modules that already failed through
`___directerrno` (`EMFILE`, `ENOMEM` from `open`, `EINVAL` for flags
DOS 3.3 lacks) still do.

| `__oserror` | Message | `errno` | Produced by |
|---|---|---|---|
| `$10` | File exists | `EEXIST` | `open` with `O_CREAT \| O_EXCL`, `rename` onto an existing name |
| `$11` | File is open | `EINVAL` | `remove`, `rename` of an open file (5.5a) |
| `$12` | Not a DOS 3.3 disk | `ENODEV` | `opendir` of a disk without a DOS 3.3 VTOC (5.9) |
| `$13` | Position out of range | `ESPIPE` | `lseek` past a B file's recorded length (5.7) |
| `$14` | No recorded end of file | `EINVAL` | `O_APPEND` to a raw file (5.3) |

Until 10.22, `$12` was "Not running under DOS 3.3" (`ENOSYS`), for
`remove`, `rename` and `exec` under ProDOS, and the codes after it were
one higher.

The numbers are in `fm.inc` (`DOSERR_*`, `LIBERR_*`). The messages use
cc65's sentence case, as the CBM and Atari lists do.

**Verified:** `oserror.s` and `oserrlist.s` were linked into a test
program and run on cc65's `sim65`. All 18 codes map to their `errno` and
message, and a ProDOS code (`$46`) maps to `EUNKNOWN`. sim65 supplies its
own `___osmaperrno` as a paravirtual call, so the test called the module
under another name. `filetest` checks `__oserror` alongside `errno` for
each failure it provokes, and `_stroserror` for one DOS and one library
code.

### 5.7 lseek

Same interface as stock cc65 (`SEEK_CUR` 0, `SEEK_END` 1, `SEEK_SET` 2;
result in `sreg:X:A`). ProDOS rules are followed where DOS 3.3 allows:

| File | End (`SEEK_END`) | Past the end |
|---|---|---|
| A, I, B | The header's length | Fails with `ESPIPE`, as `SET_MARK` past EOF does under ProDOS |
| T | The first `$00`, scanning from the start | **Allowed** |
| Raw | The end of the data, as for reads | Allowed |

- **T files may be positioned past the end** because DESIGN.md 5.2
  promises `lseek(fd, r * L, SEEK_SET)` for records of random-access
  files, and every record after the first lies beyond the first record's
  zero padding. Reading at such a position returns the record's bytes up
  to its padding; writing there extends the file, as DOS does.
- **Positions are limited to 16 bits.** The File Manager's POSITION takes
  a whole-file byte offset only when the record number is 0, and that
  offset is 16-bit (*Beneath Apple DOS* ch. 6). Larger or negative
  positions fail with `EINVAL`, the code ProDOS uses for positions out of
  its own 24-bit range. For header files, the File Manager offset
  (header length + position) must also fit 16 bits.
- `SEEK_END` on T and raw files scans byte by byte from the start, so it
  costs time proportional to the file's size.
- `O_APPEND` on T files (`seekend`) scans from the current position, not
  the start, so that repeated appends stop at once. After seeking past a
  T file's end, an appending write goes to the next `$00` after the
  current position.

### 5.8 stat

`stat` opens the file with this library's `open` and takes the size from
`lseek(fd, 0, SEEK_END)`, so the size follows the same rules as reads and
seeks.

| Field | DOS 3.3 value |
|---|---|
| `st_dev` | `slot \| (drive - 1) << 3`, the encoding stock `stat` derives from ProDOS's unit number |
| `st_mode` | `S_IFREG` (DOS 3.3 has no directories) |
| `st_size` | T: bytes before the first `$00`; A, I, B: the header's length; others: bytes to the end of the data |
| `st_access` | `DOS33_LOCKED` (`$80`) if the file is locked, else 0: DOS 3.3's only access attribute (increment 13; it was ProDOS's access byte, `$01` or `$C3`) |
| `st_type` | DOS 3.3's type (`DOS33_T_*`, 5.4), as OPEN returns it: the catalog's coding (4.4; increment 13) |
| `st_auxtype` | B: the load address; others 0 |
| `st_blocks` | 512-byte blocks, `(sectors + 1) / 2`, from the file's catalog entry: the same value `readdir` gives in `d_blocks` (5.9) |
| others | 0. DOS 3.3 keeps no dates. |

Filling `st_blocks` means `stat` reads the catalog (through the same
code as `readdir`), so `stat` pulls in the directory module: about 650
bytes more in programs that use `stat` (increment 3).

`stat` clears `errno` to tell the end of the catalog from a read error,
and puts the caller's value back on success: no library function sets
`errno` to 0 (ISO C 7.5; fixed in 10.27).

### 5.9 Directories

DOS 3.3 has no subdirectories, so a "directory" is a disk's catalog.
`opendir` takes a directory path (5.5): `"/6/2"`, `"2"`, `"."` or `""`
(the current directory), each optionally ending in `/`. Anything else
fails with `EINVAL`.

**Reading the catalog.** The File Manager's CATALOG call only prints, so
the catalog is read directly through RWTS (*Beneath Apple DOS* ch. 4, 6):

- `opendir` reads the VTOC (track 17, sector 0) and checks that it is a
  DOS 3.3 VTOC: 16 sectors per track, 122 track/sector pairs per list
  sector, and a first catalog sector on the disk. Otherwise it fails
  with the library code `$13` (5.6), which maps to `ENODEV`, so a disk that isn't
  DOS 3.3 fails at `opendir` instead of producing garbage entries.
- `readdir` follows the catalog chain one sector at a time (seven entries
  per sector). As in DOS's own search (ch. 8, `B1C9`), deleted entries
  (`$FF`) are skipped and the first never-used entry (`$00`) ends the
  catalog. At the end it returns `NULL` without changing `errno`; on a
  read error it returns `NULL` with `errno` set.
- `rewinddir` restarts at the first catalog sector; `closedir` frees the
  `DIR`. Each open `DIR` holds a 256-byte sector buffer (about 305 bytes
  in all).
- RWTS is called through DOS's own IOB (from `$3E3`), so the device
  characteristics table and last-access fields that DOS maintains stay
  valid, and with ROM banked in, as the File Manager is. RWTS return
  codes are translated to the DOS error numbers DOS reports for them
  (`rwts_maperr`, 5.6): write protect → WRITE PROTECTED (`EACCES`),
  volume mismatch → VOLUME MISMATCH (`ENOENT`), drive or read errors →
  I/O ERROR (`EIO`).

**`struct dirent`** (`include/dirent.h`):

| Field | Value |
|---|---|
| `d_name[31]` | Up to 30 characters; bit 7 cleared, trailing blanks removed |
| `d_ino` | T/S list location, track × 256 + sector (unique on the disk) |
| `d_blocks` | 512-byte blocks, `(d_sectors + 1) / 2`: the unit of POSIX |
| `d_type` | DOS 3.3's type, as the catalog stores it, without the lock bit (`DOS33_T_*`, 5.4), as `st_type` |
| `d_access` | `DOS33_LOCKED` if locked, else 0, as `st_access` |
| `d_sectors` | Length in sectors, as CATALOG shows (the DOS idiom) |

**Fields left out (decision).** cc65's ProDOS `struct dirent` also has
`d_size`, `d_ctime`, `d_mtime` and `d_auxtype`. The catalog has no byte
size, no dates and no load address; a byte size would take opening each
file (and, for T files, scanning it). Rather than fill them with zeros,
the DOS 3.3 struct leaves them out, so **code that relies on them fails
to compile** instead of silently reading wrong values. `stat` gives a
file's exact size and load address.

---

### 5.10 exec

**Problem:** stock `exec()` fails under DOS 3.3. Its first step,
`mli_file_info_direct`, goes through `callmli`, which returns `$01` when
`__dos_type == 0`, so `exec()` sets `ENOSYS` (verified, `exec.s`, `mli.s`).
Raised by polluks on cc65/cc65#3050: "What about exec() via COUT ^D?"

**Approach (decision):** keep stock `exec()`'s structure: validate, shut
down the C library, then hand off to a stub in page 3. Replace the stub's
ProDOS loader with a DOS 3.3 command sent through `COUT`. DOS runs the
program the same way it would after the user typed the command.

| Option | Pros | Cons |
|---|---|---|
| DOS command through `COUT` (`BRUN`/`RUN`) | DOS's own loader; `RUN` of A files comes free; small stub | Errors after the hand-off are DOS's, not `errno` |
| Load the B file with the File Manager in the stub, `JMP` to it | Errors could be caught later | The stub needs FM buffers and the parameter list after `free`; larger than page 3 allows; duplicates `BLOAD` |

#### How DOS takes the command (verified, *Beneath Apple DOS* ch. 8)

- DOS's video intercept (`$9EBD`) runs a state machine. In state 0 (start
  of line), a Ctrl-D (`$84`) switches to state 1. State 1 stores each
  character at `$200` + index, the Ctrl-D included. On a carriage return
  it runs the command parser (`$9FCD`).
- A CR in state 2 (ignoring a non-command line) or state 3 (after input)
  sets state 0, so **the stub prints a CR first** and gets to state 0
  from wherever the program left off. a2lib never uses DOS's own WRITE
  mode (state 4), because it calls the File Manager directly.
- State 0 checks for Ctrl-D whether or not BASIC is running. `read.s`'s
  `initprompt` only stops DOS from scanning *input* for commands, so it
  doesn't get in the way.
- `BRUN` (`$A38E`) does a `BLOAD`, reinstalls DOS's intercepts, and
  jumps to the file's load address.
- `$3EA` (`$A851`) reinstalls an intercept only if it isn't already in
  place, so it's safe to call when DOS is already hooked in.
- The display backends' destructors put back the hooks they found
  (verified, `vt.s` `vtdone`, `s80.s` `s80done`). After `donelib`, CSW is
  what it was when the program started.

#### Sequence

Before the point of no return. Every failure returns -1 with `errno` set,
as stock `exec()` does:

1. **Name:** `fm_tempfcb`, `fm_begin`, `fm_name`. Paths work as in
   `open` (5.5). Errors: NO BUFFERS AVAILABLE → `ENOMEM`, SYNTAX ERROR →
   `EINVAL`, and SYNTAX ERROR for a name with a comma, which DOS's command
   parser would end there (increment 14).
2. **Exists, and its type:** OPEN without allocating (X ≠ 0, as
   `fm_isopen` does), take `FM_TYPE` and mask the lock bit (as `open.s`
   does), CLOSE, `fm_freefcb`. OPEN errors are mapped by `fm_maperr`
   (`ENOENT`, `EIO`, …).
3. **Verb:**

   | FM type | Command | Notes |
   |---|---|---|
   | `$04` B | `BRUN` | The counterpart of stock's BIN path |
   | `$02` A | `RUN` | A DOS 3.3 idiom; stock has no BASIC case. `cmdline` must be NULL or `""`, otherwise `EINVAL` (an Applesoft program can't receive it, and the guiding principle rules out dropping it silently) |
   | others | — | FILE TYPE MISMATCH (`$0D`) → `ENOEXEC`, the errno stock `typerr` gives |

   I files are rejected. Whether Integer BASIC is present can't be known
   until DOS tries, which would be after the hand-off.
4. **Build the command** in the stub's buffer: `$84`, verb, space, the
   name from `fm_namebuf` with its `$A0` padding trimmed, then
   `,S<slot>,D<drive>`, then `$8D`. Slot and drive are written out
   explicitly, so DOS opens the file that was just checked. Worst case is
   43 bytes: `^D` + `BRUN` + space + 30 + `,S7,D2` + CR. (Until increment
   14, a `,V<n>` suffix could follow, making 48.)
5. **Copy the stub** to page 3 (`target = DOSWARM - size`, with stock's
   `.assert target >= $300`). a2lib uses nothing else in `$300`–`$3CF`
   (checked by grep).

Point of no return. Same as stock from here:

6. Reset SP to `$FF`. Store up to 127 bytes of `cmdline`, `'\0'`
   included, at `$0100`. Point `done+1` at `target`, then
   `jmp exit_with_params`. The destructors close every file
   (`closeallfiles`), restore the hooks and the IRQ vector, and `_exit`
   restores the zero page.

The stub, entered from `done` with ROM banked in:

7. `JSR $3EA`: reconnect DOS's intercepts (does nothing if already
   connected). Then print a CR, *before* step 8, while DOS still sees a
   running program. A program that has just read the keyboard leaves
   DOS's intercept in its input state (3). There a CR goes to state 0,
   unless BASIC is in immediate mode, in which case DOS collects it as a
   command line (*Beneath Apple DOS* ch. 8, `$9F2F`). So the CR has to
   come before the reset puts DOS in immediate mode. (Decided in
   implementation; the probes printed nothing before their command.)
8. Set `CURLIN+1 = $FF` and `PROMPT = $DD` (`]`), and clear `ERRFLG`
   (`$D8`). This puts DOS's state back to how it is when a user types the
   command, undoing `read.s`'s `initprompt`. Every DOS error goes through
   one handler (`$A6D5`), which skips its message while ONERR is set and
   passes the error to Applesoft while a program seems to be running
   (*Beneath Apple DOS* ch. 8). **(verified, probes below)** With the
   reset, a failed `BRUN` prints FILE NOT FOUND and returns to the `]`
   prompt. Without it, the same failure adds `BREAK IN 32868` (`$8064`:
   `initprompt`'s `$80` in `CURLIN+1`), because Applesoft takes the error
   as its own program's.
9. If `cmdline` isn't empty, copy the argument tail (below) from `$0100`
    to `$200 + L`, where L is the command's length (patched in at step
    5).
10. Print the command through `$FDED`. DOS runs it on its final CR.
11. `JMP DOSWARM`, for a B program that ends with `RTS`: DOS's exit
    (`$9FB3`) restores the S it had on entry, which returns into this
    stub.

The stub is 115 bytes, at `$35D`–`$3CF` (120 at `$358` before increment
14 dropped the volume suffix): 70 bytes of code, a length
byte, and 44 bytes for the command and its terminator.

#### Passing `cmdline` (decision)

There's no DOS 3.3 convention. The command has to end at its CR (any
text after the name is a DOS SYNTAX ERROR), so the arguments go in page
2 *after* the command, where DOS's line collector doesn't write:

```
$200: $84 "BRUN NAME,S6,D1" $8D   $00 $B2 cmdline… $00
      └── stored by DOS ───────┘   └── written by the stub ──┘
```

- `$B2` is the REM token that stock `mainargs.s` looks for (the
  BASIC.SYSTEM convention, from polluks's original mainargs code).
- The `$00` before it is the marker. Keyboard input is stored with the
  high bit set, so a typed line never has `$00` after its CR.
- **Programs linked with a2lib** get a modified `mainargs.s`. Under DOS
  3.3, if `$200` is `$84` and the first `$8D` is followed by `$00 $B2`,
  it parses the arguments after the `$B2`, then overwrites the `$00`.
  That way, if the user later types a line of exactly the same length,
  the old arguments aren't picked up again.
- In that version, argv[0] points to an empty string in DATA, not to
  `FNAM` (`$281`). Under DOS 3.3, stock makes argv[0] `""` by writing `$00`
  to `$281`, *before* copying the arguments. That is deliberate and fits
  stock's documented 127-character limit (`BUF_LEN`), so it isn't a cc65
  bug. But a 43-byte command plus a 129-byte tail can reach `$2AC`, and
  that write would corrupt exec()'s tail.
- **Other programs** (stock `mainargs`, Applesoft) see no arguments.
  Stock's scan for `$B2` stops at the `$00`. One exception: a high-bit
  `'2'` in the command (`PROG2`, `,D2`) is also `$B2`. Stock then starts
  parsing right after it, hits a high-bit character and stops, so it
  still sees no arguments rather than garbage. That stays true because
  every byte of the command has its high bit set.
- argv[0] stays `""`, as under DOS 3.3 today. Setting it to the program's
  name is possible later; the name is in the command.

#### Limits (documented, not fixed)

- After the hand-off, failure is DOS's: a message and the `]` prompt.
  Step 3 rules out the expected causes (missing file, wrong type).
- Stock `exec()` doesn't check whether a BIN's load range overlaps its
  loader, so this doesn't either. A B file loaded into page 2 or 3 would
  overwrite the stub.
- `cmdline` is truncated at 126 characters, as in stock.

#### Files

| File | Change |
|---|---|
| `libsrc/dos33/exec.s` | New: replaces stock `exec.o` in `a2lib-dos33.lib` |
| `libsrc/dos33/mainargs.s` | Modified copy: the argument marker; argv[0] not at `FNAM` under DOS 3.3 |
| `libsrc/dos33/VENDORED.md` | Lists `mainargs.s` |
| `test/exectest.c`, `test/argtest.c` | Tests, below |
| `Makefile` | Builds `exectest`, `exectestvt` (VideoTerm library), `execatest` (`-DEXECA`) and `argtest` |
| `test/emutest.sh` | Runs `exectest`, `exectest-vt` and `execatest`, on the exec disk with the probes; `argtest` goes on that disk too |

#### Tests (`make emutest`)

`exectest` first reads a line (the runner types it), so DOS is in its
input state when the stub runs (step 7), and `read.s` is linked, as in
any program that reads. It writes a T file and `EXECA`, an Applesoft
program (`10 PRINT "EXECA OK"`, tokenized), then checks the failures.
Each must return -1 with this program still running: a missing file
(`ENOENT`), a T file (`ENOEXEC`), a bad name (`EINVAL`), and an A file
with a `cmdline` (`EINVAL`). Then it execs `ARGTEST,D2` with
`PRE=4/4 ONE "TWO 2" THREE ` followed by 100 X's: 126 characters, the
most stock keeps, so the tail reaches `$295`. The `,D2` in the command
puts the `$B2` hazard in the test. `argtest` checks argc 6, argv[0] `""`,
`PRE=4/4` (exectest's own checks), each argument, and that the marker
was cleared, and prints "ALL n PASSED".

| Run | Checks |
|---|---|
| `exectest` | The above; then the runner types `BRUN ARGTEST,D2`, and `argtest` must get no arguments (DIRECT OK): a typed line isn't taken for exec's |
| `exectest-vt` | The same, built with the VideoTerm library and run with the card: the backend's destructor puts DOS's hooks back, and DOS sees the command |
| `execatest` | `RUN` of `EXECA` (no cmdline): EXECA OK, no error |

**Simulated before the first emulator run:** `exec.s` and `mainargs.s` were
run in a 6502 simulator (py65), with stand-ins for the File Manager glue
and a model of DOS's video intercept: the five failures before the
hand-off; the command sent (`$8D`, `$84`, `BRUN ARGTEST,S6,D2`, `$8D`, all
with the high bit set); the first CR while DOS still sees a running
program, and the reset done before the command runs; the tail at
`$200 + L`; `mainargs` taking all six arguments back, clearing the marker,
and finding none on a second start; `RUN` with a volume (`,V254`) and no
tail for an A file. All 20 checks pass. The simulation can't show what
DOS and Applesoft really do; the emulator runs do.

**Verified with `make emutest`** (ReplicApple2Plus 1.11.0's runner, DOS
3.3 System Master): `exectest` and `exectest-vt` pass all 8 of argtest's
checks and DIRECT OK; `execatest` shows EXECA OK; all 22 runs pass. With
the VideoTerm, exectestvt's output goes to the card and argtest's to the
40-column screen, so the backend's hooks were put back and DOS still saw
the command. A typed command's CR isn't echoed before the program runs,
so DIRECT OK follows `]BRUN ARGTEST,D2` on the same line; the pass
condition matches it at the end of the line.

#### Probes (verified before implementation)

Run with `make emutest` (ReplicApple2Plus's runner, DOS 3.3 System
Master), all passing:

| Run | Shows |
|---|---|
| `bloadprobe` | A running program can send DOS commands through `$FDED` (BSAVE, then BLOAD, round trip); DOS stores `$84`, the command and `$8D` at `$200`; BLOAD leaves `$230`–`$2FF` unchanged, so the argument tail survives `BRUN`'s load (`$A38E` runs BLOAD) |
| `errprobe` | The hand-off (`main` returns, the destructors run, `done` jumps to a page-3 stub) and step 8: with `ERRFLG` set beforehand, a failed `BRUN` prints FILE NOT FOUND, no Applesoft error, and BASIC answers at `]` |
| `errproberaw` | The same without step 8: FILE NOT FOUND, then `BREAK IN 32868` |

The error probes link `read.s` on purpose (`keep_read` in `errprobe.c`):
`initprompt` is a constructor in `read.s`, so a program that only prints
never sets `PROMPT` and `CURLIN+1`, and the first run of the probes, which
didn't link it, couldn't tell the variants apart. `emutest.sh` pass
conditions may now join several EREs with ` && `, with `!` for one that
must not match. The probes have a disk of their own
(`build/emu/a2libprobes.dsk`), as `nettest` does: on the main test disk
they left `filetest` 12 free sectors, and it failed 14 of 68 checks
(LSEEK on) for lack of space. Verified: all 19 runs pass (ReplicApple2Plus
1.11.0's runner, including `nettest`).

**Upstream:** in a `-t apple2dos33` target (proposal item 2), `exec.s`
and the `mainargs.s` change go in with the target, not as a separate PR.

### 5.11 A disk write-protected while a file is open

DOS's File Manager holds a file's last data sector, its T/S list and the
VTOC in buffers, and writes them on CLOSE; `closedirect` (`open.s`) also
rewrites an A, I or B file's header then. On a disk protected after the
writes, those fail with WRITE PROTECTED (`EACCES`). Stock `close.s`
keeps the fd, and its buffer, when `closedirect` fails, so the program
can make the disk writable and close again, saving every byte: a file
DOS couldn't close is still open.

`test/wptest.c` checks this, with ReplicApple2Plus's runner protecting
drive 2 mid-run (`--protect`, `--writable`): bytes appended to a B file,
the disk protected, `close` failing with `EACCES`, the disk made writable,
`close` succeeding and the file holding all its bytes. It passes as
the layer stands (10.29): no change was needed.

Not covered: a header rewrite that fails while CLOSE succeeds, which
would leave the fd open on a file DOS has closed. Protecting the disk
should fail both, and nothing else here can fail only the first. Nor is a
read-only `open` of an A, I or B file with no data at all (it gets a
header on close): neither a2lib nor DOS's commands make such a file.

## 6. DOS 3.3 interrupts

**(verified)** cc65's `initirq` simply asks the ProDOS MLI to allocate an
interrupt and prints "FAILED TO ALLOC INTERRUPT" otherwise. `crt0.s`
already installs an IRQ forwarding routine in the Language Card vectors
for non-ProDOS programs. **Decision:** a DOS 3.3 `initirq`/`doneirq` that
hooks the monitor's IRQ vector at `$3FE`, chaining the previous handler,
selected at link time like the other modules.

### 6.1 Design (increment 4)

`libsrc/dos33/irq.s` replaces stock `irq.s`. Until 10.22 it kept stock's
ProDOS path, which allocates an interrupt through the MLI.

**The banking problem.** Under DOS 3.3, `crt0` points the IRQ vector in
Language Card RAM at `irq_6502`, which switches ROM in and jumps through
ROM's vector. A program interrupted while running with LC RAM enabled,
which is cc65's normal state, would resume with ROM visible instead of
its LC code. A 16K Language Card on a II+ has no switch that reports
whether LC RAM or ROM is enabled for reading (the //e's `$C011`/`$C012`
don't exist), so a handler can't save and restore that state.

**Decision: two entry points, as ProDOS does.** The way an interrupt
arrives tells which bank was enabled:

- **LC RAM enabled:** the CPU takes the vector at `$FFFE` from LC RAM.
  `initirq` replaces `crt0`'s `irq_6502` there with `lcirq`, which saves
  A, X and Y, calls the interruptors, and returns without touching the
  banking.
- **ROM enabled** (during `COUT`, `RDKEY`, File Manager and RWTS calls,
  or on a machine without a Language Card): the CPU takes ROM's vector,
  to the Autostart ROM's IRQ handler at `$FA40`, which saves A in `$45`,
  passes a BRK to the monitor, and jumps through `$3FE`. `initirq` points
  `$3FE` at `romirq`, which saves X and Y, calls the interruptors, and
  restores A from `$45` before `RTI`, the convention for DOS 3.3 IRQ
  handlers.

Either way, the interrupted code resumes with the banking it had.

**Unhandled interrupts and BRK** go where they went before `initirq`: an
interrupt no interruptor handles goes to the previous `$3FE` handler,
and a BRK (or unhandled interrupt) in LC RAM goes to `crt0`'s
`irq_6502`, which, as in stock cc65, leaves ROM enabled. The previous
handlers are stored into absolute `JMP` instructions in the DATA segment
rather than jumped to indirectly, because an indirect `JMP` through a
variable that ended up at `$xxFF` would hit the NMOS 6502's page-wrap
bug.

**`doneirq`** restores `$3FE` and the LC RAM vector at exit.

**Startup order: a2lib's `crt0.s` (decision, from the first run).** Stock
`crt0` runs the module constructors (`initlib`, which calls `initirq`)
*before* it patches the RESET and IRQ vectors in LC RAM for DOS 3.3. So
`initirq` installed `lcirq`, and `crt0` then overwrote it with
`irq_6502`. The first run showed this: on the simulated LC RAM path, the
interrupt was handled (it went through `irq_6502`, ROM and `$3FE` to
`romirq`), but ROM was left enabled, failing the banking check. It also
meant `initirq` saved whatever was in LC RAM before `crt0`, not
`irq_6502`, as the handler to chain to. Options considered:

| Option | Assessment |
|---|---|
| Install `lcirq` lazily, from `romirq`, on the first interrupt that arrives through `irq_6502` | Keeps the bug for that first interrupt, which could crash a program running LC code |
| Replace `zerobss` or `callmain` to get a hook after `crt0`'s patch | Forks a stock module only for its timing; no simpler than forking `crt0` |
| **Fork `crt0.s`, patching the vectors before `initlib`** | **Chosen.** The smallest change in behavior: only the vector patch moves; constructors still run before the LC segment is copied, as in stock cc65 |

a2lib's `libsrc/dos33/crt0.s` is a modified copy of stock `crt0.s` that
patches the vectors, switches back to ROM with LC RAM write-protected
(the state at entry), then calls `initlib`. Like `write.s`, it belongs in
the upstream proposal; it costs 9 bytes of startup code, which is freed
after initialization.

**BSS is cleared after the constructors.** `crt0` calls `zerobss` after
`init` returns, so anything a constructor stores in BSS is lost. The
first draft kept `irq.s`'s "installed" flag in BSS, so `doneirq` would
have skipped restoring the vectors at exit. The flag is now in DATA, as
stock `irq.s` keeps its `int_num`.

**Disk I/O is safe with interrupts enabled.** DOS 3.3's RWTS masks
interrupts while it runs (*Beneath Apple DOS* ch. 2; ch. 8 at `$B7B5`,
"Disable interrupts and call RWTS"); interrupting RWTS while writing
could destroy a disk under DOS 3.1. The File Manager and RWTS wrappers
therefore need no extra masking.

**Size:** 128 bytes resident (stock: 29), plus 115 bytes of startup code
in the `ONCE` segment, which is freed after initialization. Only
programs that declare interruptors link it.

### 6.2 Testing

No card emulated by ReplicApple2Plus raises IRQ yet (the CPU models the
IRQ line, but no device asserts it), so the tests simulate interrupts in
software (`test/irqtest.s`): they push the return address and a status
byte with B clear, as the CPU does, set I, and jump through the vector
at `$FFFE` as currently enabled. With LC RAM enabled, that enters
`lcirq`; with ROM switched in, it enters the real Autostart ROM handler,
which goes through `$3FE` to `romirq`. Each path is checked for the
interruptor being called, the same bank being enabled after `RTI`, and
A, X and Y surviving (A through `$45` on the ROM path). Declaring the
test interruptor also makes every test run go through `initirq` and
`doneirq`, so all the file tests run with the handlers installed.

**Not covered:** the CPU's own interrupt entry, and interrupts arriving
at arbitrary points (inside `COUT`, a File Manager call, or RWTS). These
need an emulated card that raises IRQ (section 10.5).

### 6.3 Cooperative timer and software clock (increment 7)

**Purpose.** A utility for programs that need a regular "go" interval
(periodic work while idle, timeouts), with three clients in the library
itself: the 80 × 24 model's position indicator (a gauge hidden after a
delay; the 40-column window's, then Soft-70's), IP65's timer, and a
software clock for `time()` and `clock_gettime()` under DOS 3.3, which
programs can set from an Internet time server (IP65 includes an SNTP
client, `sntp_get_time`).
Millisecond accuracy isn't a goal.

**The constraint.** A stock II+ has no timer and no vertical-blank
interrupt (the //e's `$C019` doesn't exist on it), so nothing can
interrupt a program after a delay. The timer is therefore
**cooperative**: time advances only while the program waits inside the
library, in loops whose cycle counts are known, and callbacks run only
at those points. While a program computes without calling the library,
the count stands still. Interactive programs spend nearly all their time
waiting for keys or packets, so in practice the count stays close to
real time; a program that needs wall-clock accuracy over long busy
stretches resyncs from a time server.

**State of the art (verified).**

- cc65 has no `clock()` for the Apple II (`time.h` defines no
  `CLOCKS_PER_SEC` for it), and its `clock_gettime` reads the ProDOS
  clock (`libsrc/apple2/gettime.s`), so under DOS 3.3 there is no time
  base at all. `time()` is built on `clock_gettime`.
- IP65's Apple II timer (`drivers/a2timer.s`) is a stopgap: with no
  timing hardware, every call to `timer_read` busy-waits about 33 ms
  (`JSR $FCA8`) and adds 33 to its millisecond count, so each network
  timeout check costs 33 ms.

**Time base.** The monitor's random-seed counter, `RNDL`/`RNDH`
(`$4E`/`$4F`), which keyboard wait loops increment on every pass. cc65's
`cgetc` loop (`INC RNDL` / `BNE` / `LDA KBD` / `BPL`) takes 15 cycles per
pass, plus 4 when `RNDL` wraps, so one increment of `RNDH` (a **tick**)
is 255 × 15 + 19 = **3,844 cycles**. Every wait loop the library owns
uses the same structure and checks the timer when `RNDH` increments.

**Milliseconds without division (Bresenham).** A tick is a non-integer
number of milliseconds. The II+'s average CPU clock is
14,318,180 Hz × 65 / 912 = 1,020,484 Hz (a cycle is 14 cycles of the
14.31818 MHz master clock, except the last of each 65-cycle scan line,
which is stretched by 2), so a tick is 3.766839 ms. Rather than divide,
the timer distributes the fraction with a Bresenham-style error
accumulator: each tick adds 3 to a 32-bit millisecond counter and 148 to
an 8-bit error term; when the error reaches 193, it subtracts 193 and
adds one more millisecond. 3 + 148/193 matches the exact ratio to
0.1 ppm (0.01 s/day), far below the tolerance of the II+'s crystal. The
counter wraps after 49.7 days. The same technique carries milliseconds
into seconds for the software clock (add each tick's milliseconds to a
sub-second count; at 1,000, subtract 1,000 and add a second), so no
32-bit division is ever needed.

**Revised in implementation: the tick includes the tick routine.** The
wait loop is suspended while `a2_tick` runs, so a tick is 3,844 cycles
*plus* the routine's own time; leaving that out would have run the count
2.4% slow (about 35 minutes a day). The routine's common path (no timer
active, no second boundary) was counted by hand at 90.6 cycles averaged
over its branches, and **measured in sim65 at 90.5** (87.5 for
`JSR a2_tick` and `RTS`, plus the 3-cycle `JMP` through the hook vector).
So a tick is **3,934.6 cycles = 3.855602 ms**, and the timer uses
**3 + 160/187 ms** per tick (`TICK_NUM`/`TICK_DEN` in `timer.inc`); the
fraction matches that tick length within 3.5 ppm. 1,000 ticks are 3,855
or 3,856 ms.

**Layout dependence.** On the 6502, a taken branch that crosses a page
boundary, and an indexed load whose address does, take one more cycle,
so `a2_tick`'s cost depends slightly on where the linker places it and
its tables. A later sim65 build, whose only change was in the startup
code, measured 88.5 cycles (166.6 with a timer active) instead of 87.5
and 159.6. Each cycle is about 0.025% of a tick (roughly 20 seconds a
day), so the clock's accuracy is limited to about that order by layout,
not by the 3.5 ppm fraction; this is well below the biases below.

**Known biases (uncompensated):**

- **While any timer is active,** each tick costs about 72 more cycles
  (measured: 159.6 with one active timer), so counted time runs about
  1.8% slow; each further active timer adds roughly 0.5%. The cost
  depends on how many timers run, so it isn't folded into the constant.
- **During stdio input,** the `KSW` routine saves and restores registers
  and switches banks around each tick (about 46 cycles), so counted time
  runs about 1.2% slow while a program waits in stdio input.

Programs that need an accurate clock resync it (from a time server) now
and then, which these biases don't change. Compensating them (a second
error term for the active-timer path) is a possible refinement.

**The Autostart ROM's input path (verified** by disassembling the II+
system ROM used with ReplicApple2Plus, 12 KB at `$D000`, CRC32
`1D05C1B1`, RESET vector `$FA62`):

- `RDKEY` (`$FD0C`): `LDY CH`, `LDA (BASL),Y`, saves that character,
  draws a flashing cursor in its place (`AND #$3F`, `ORA #$40`), and
  jumps through `KSW` with **A = the original character under the
  cursor and Y = `CH`**.
- `KEYIN` (`$FD1B`, the default `KSW` routine): `INC RNDL` / `BNE` /
  `INC RNDH` / `BIT KBD` / `BPL` (back to the top), then, once a key is
  pressed, `STA (BASL),Y` (restores the character under the cursor),
  `LDA KBD`, `BIT KBDSTRB`, `RTS`, returning the key in A with X and Y
  unchanged. Its loop is 15 cycles per pass, plus 4 when `RNDL` wraps,
  so it advances `RNDH` at the same 3,844-cycle tick as `cgetc`.

The replacement `KSW` routine keeps this contract exactly: same loop,
same restore through `(BASL),Y`, key in A, X and Y preserved; it adds
only the tick check on each `RNDH` increment.

The same disassembly confirms the IRQ path 6.1 relies on: `$FA40` is
`STA $45`, `PLA`, `PHA`, three `ASL`s (the pushed status's B flag into
the sign bit), `BMI $FA4C` (BRK, to the monitor), `JMP ($03FE)`.

**Installing the input routine under DOS 3.3 (revised after the first
emulator run).** DOS 3.3 normally keeps its keyboard intercept (`$9E81`)
in `KSW` and the true input routine at `$AA55`. On every character
through either of its intercepts, DOS copies its saved true handlers
into `$36`-`$39` (`$9ED1`) and reinstalls its intercepts on the way out
(`$A851`, saving whatever is then in `KSW` as the new true handler)
(*Beneath Apple DOS* ch. 8). The first version stored the routine in
`KSW` directly; the first character of output then replaced it with the
ROM's `KEYIN`, which DOS filed away as the true handler, so stdio input
never reached the routine (the INPUT checks failed: no callbacks, no
counted time). Now, when DOS's intercept is in `KSW` (`KSW` equals the
address DOS keeps at `$9D02`), the routine is installed as DOS's true
input routine at `$AA55` instead, and DOS calls it; DOS restores the
registers before that call, so the routine still receives the character
under the cursor in A and `CH` in Y. Otherwise it goes into `KSW`
directly. Exit restores whichever hook was changed.

**Polling points**, where time advances and due callbacks run:

| Point | How time is counted |
|---|---|
| `cgetc` | Its wait loop, in every library (the base library gains a modified `cgetc.s` for this) |
| stdio input | A replacement `KSW` input routine with the same loop, installed while the timer is in use and restored at exit (as `CSW` is), mirroring the Autostart ROM's `KEYIN` (below) |
| `kbhit` | While the timer is in use and no key is pending, waits one counted tick (3.9 ms), so loops that poll `kbhit` advance time and run callbacks |
| `a2_idle()` | Waits one counted tick, for programs' own idle loops |
| IP65's `timer_read` | A replacement that calls `a2_idle()` once (3.9 ms instead of IP65's 33 ms) and returns the millisecond count |

**Linked on demand, as reflow is (3.2).** The library's wait loops call a
hook vector (a 3-byte `JMP` in DATA, initially to an `RTS`) at each tick.
The timer module is linked only if a program calls its functions, and
installs itself in the vector when started. Programs that don't use the
timer pay a few bytes of hook and an extra `JSR`/`RTS` every 3.9 ms of
waiting.

**API (`include/a2timer.h`):**

| Function | Purpose |
|---|---|
| `unsigned long a2_millis (void)` | Milliseconds counted since startup |
| `void a2_idle (void)` | Wait one counted tick and run due callbacks |
| `unsigned char a2_timer_start (unsigned ms, void (*fn) (void), unsigned char periodic)` | Start a one-shot or periodic timer; returns a handle, or a failure value when all slots are in use |
| `void a2_timer_stop (unsigned char handle)` | Stop it |
| `unsigned long a2_clock_age (void)` | Seconds since the software clock was last set, or `A2_CLOCK_UNSET` |

- A fixed table of 4 timer slots, to keep memory small. A one-shot
  timer's slot is freed when it fires; a periodic one's when stopped.
- Internally, `a2_timer_arm` (interval in ticks) and `a2_timer_restart`
  touch no zero page, so the window's gauge can use them from inside
  `cputc` (where `cputs` keeps `ptr1` and `chline` `tmp1`/`tmp2`).
- Intervals are rounded to ticks (3.9 ms), suitable for "go" intervals.
- **Callback rules:** callbacks run inside polling points, so they must
  be short; they may use conio and stdio output; they must not wait for
  keys (`cgetc`, stdio input) or call `a2_idle`. The dispatcher doesn't
  dispatch again while a callback runs. Because the `KSW` routine runs
  with ROM switched in (as `RDKEY` calls it), the dispatcher switches LC
  bank 2 back in (`$C080`) around callbacks and restores ROM afterward,
  so callbacks always run in cc65's normal banking.

**Software clock (DOS 3.3).** a2lib replaces `clock_settime` and
`clock_gettime` with a software clock: `clock_settime` records the time
given (for example, from `sntp_get_time`), and `clock_gettime` returns it
plus the seconds counted since, so `time()` works too. It drifts slow by
whatever time the program spends computing, so programs resync
occasionally.

- **Before the clock is set, `clock_gettime` returns the up-time
  (decision):** the seconds counted since the program started, from an
  epoch of 0 (1 January 1970). Programs can measure elapsed time without
  a time server.
- **Whether the clock has been set (decision):** a2lib provides
  `unsigned long a2_clock_age (void)`, the seconds since the clock was
  last set, or `A2_CLOCK_UNSET` (`0xFFFFFFFF`) if it never was. One call
  answers both "was it ever synchronized?" and "is it time to resync?":
  `if (a2_clock_age () > 3600) resync ();` also catches the unset case,
  since `A2_CLOCK_UNSET` exceeds any threshold. A plain "set" flag would
  answer only the first.

**IP65 linking.** ld65 scans each library once (section 2), so a
replacement `timer_read` placed in a library listed before IP65's would
not be used: IP65's modules reference `timer_read` only after a2lib's
library has been scanned. The replacement therefore ships as an object
file to list explicitly on the link line.

**Machines (decision):** NTSC Apple II+ only for now. The Europlus (PAL)
has a different master clock, so its tick length differs; the tick
constants (3 ms + 148/193) are kept in one place so PAL values can be
added later.

**The window's position indicator (decision), the timer's first
client.** After the window pans, a gauge appears and the timer hides it
again; the indicator is drawn over the screen and restored from the
80 × 24 buffer, so it never changes the program's screen.

- **40-column window:** `[====....]` in inverse video in the top-right
  corner (10 characters). Each of the 8 cells stands for 10 columns and
  the window covers 4, so the three positions read exactly:
  `[====....]` (columns 0-39), `[..====..]` (20-59), `[....====]`
  (40-79). Default display time about 1 second (proposed).
- **Soft-70 (planned with it, section 3):** Soft-70 shows 70 of the 80
  columns, so only 10 are hidden and there are two useful positions. In
  hi-res, the indicator can be a thin bar on the bottom scanline: a
  dotted track the full 280-pixel width with a solid thumb covering the
  visible 70/80. It hides almost nothing, and drawn with XOR it is
  removed by drawing it again, without reading the text back. It
  overlays the bottom scanline of row 23, so the Soft-70 font should keep
  each glyph's bottom scanline blank; to settle when that font is
  designed.

**Interrupt-driven improvement (later).** With a card that interrupts
periodically (a Mockingboard's timers, a mouse card's 60 Hz interrupt, a
clock card), an interruptor could advance the count exactly, using the
interrupt support in 6.1. Not the default, since a stock II+ has no such
card, and ReplicApple2Plus doesn't emulate one yet.

**Size (measured).** The estimate before implementation (300-400 bytes)
was low. Resident code and data:

| Module | Bytes | Linked by |
|---|---|---|
| `timer.s` | 836, plus 46 of startup code (freed) | Any use of the timer, the clock, or the window's gauge |
| `gettime.s`, `settime.s` | 179 (+10 BSS), 156 | `clock_gettime`, `time()`; `clock_settime`, `a2_clock_age` |
| `tick.s` | 5 | Any `cgetc` or `kbhit` |
| Hook in each wait loop | 3 per loop | Same |

Most of `timer.s` is the dispatcher's save and restore, `a2_timer_start`'s
24-bit ms-to-tick arithmetic, and the slot tables. Programs that use none
of these pay only the hook: `filetest` is unchanged, `vttest` grew by 11
bytes. The window's gauge adds about 150 bytes to `win.s`, and because
the gauge uses the timer, programs linked with `a2lib-c40win.lib`
include `timer.s` (`wintest` grew by 1,374 bytes, gauge checks included).

**Testing in sim65 (`make simtest`).** cc65's 6502 simulator runs the
real modules, built for its `sim6502` target, with stubs for the few
Apple II-only imports: `test/sim/timersim.c` checks the Bresenham
arithmetic against an exact model, ms-to-tick rounding (100 ms = 26
ticks), one-shot and periodic timers, slot limits, zero-page
preservation and the clock, and measures `a2_tick` with sim65's cycle
counter; `test/sim/gaugesim.c` linked the real `win.s` (at `$0C00`, so
the text screen is free) and checked what the gauge leaves on screen
(until 10.36; its timing checks are now in `s70sim.c`). It
caught a real defect: the 32-bit add and subtract loops in the clock
modules ended with `CPX #4`, which overwrote the carry chaining the
bytes, so any nonzero clock offset gave wrong times (the up-time check
passed only because the offset was 0). They now test the loop end with
`EOR`, which leaves the carry alone.

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

- **Emulator:** ReplicApple2Plus. Its headless runner
  (`replicapple2plus-run`, from 1.8.0) boots a disk, types into the
  emulated keyboard, runs until given text is on screen, and writes the
  screen's text: the text page, the VideoTerm's 80 columns, or a Soft-70
  screen found by its text marker (3.9). 1.9.0 completed it for every
  Apple II project: it builds the machine from a slot configuration and
  plug-ins as the application does (`--config`, `--folder`, `--plugins`),
  so a run can have the Uthernet II or SoftCard II installed; it can pace
  a run at the II+'s 1.023 MHz (`--real-time`); and it takes the boot
  prompt to wait for (`--prompt`, `A>` for CP/M).
- **Speed (decision).** Runs are unthrottled by default, several times
  faster than a II+, and that doesn't change what a program does: the
  emulation counts cycles, and a II+ has no clock but its CPU, so delay
  loops, disk rotation and a2lib's timer all see emulated time, and the
  runner's own times (`--wait`, `--timeout`) are emulated seconds too.
  `timertest` gives the same results headless as in the application. The
  exception is anything the outside world paces in real time: a network
  server answers in wall-clock time, so an unthrottled program's
  timeouts would expire several times too soon. Such runs use
  `--real-time` (the network run below; unthrottled, it fails). `make emutest MASTER=...`
  (`test/emutest.sh`) builds a test disk with AppleCommander, runs each
  test program with the DOS 3.3 System Master in drive 1 and the disk in
  drive 2, with and without the VideoTerm as each needs, and checks each
  screen's summary line ("ALL n PASSED", or "0 FAILED" for the CSW
  tests). Screens are kept in `build/emu/`. `RUNS="..."` picks runs by
  name; `RUNNER` and `AC` name the tools if they aren't on `PATH`.
  `SNAP=folder` adds the runner's `--snap` (ReplicApple2Plus 1.11.0) to
  each run once its last screen shows, saving it as `<run>.png` on the
  `MONITOR` given (default green); `make screenshots` uses it for the
  README's Soft-70 picture.
  Scripted input: the CSW tests and `timertest` are typed a word at their
  prompt (`timertest` after a 0.2 s pause, since it checks that 100 ms
  pass during input). `filetest` and `timertest` end with their summary
  rather than "PRESS A KEY", so a failing run reaches the timeout (300 s
  of emulated time) before it is reported, with the summary it shows.
  Verified with the 1.8.0 runner (built from its tag) and the DOS 3.3
  System Master: all 15 runs pass in about 21 seconds, with the counts of
  the manual runs (`filetest` 65, `timertest` 19, `vttest` 15/16,
  `wintest` 22/16, `s70test` 23/16, reflow 6/6/7/7, CSW 0 failed); with
  `s70test`'s old inverse-check fault put back, its run fails with "1 OF
  23 FAILED" and the screen shows the failing check.
- **Network run:** `test/nettest.c` exercises the IP65 timer driver (6.3)
  with IP65 itself, which until now was checked only by its link map
  (10.8). Linked with `lib/a2lib-ip65.o` ahead of IP65's libraries, it
  brings up IP65 on an Uthernet II in slot 3, leases an address from the
  emulated card's DHCP server, connects to an echo server on the host
  through the card's gateway (10.0.2.2), and times the server's
  two-second delay before it echoes, polling with `ip65_process` and
  `a2_idle` as a program's idle loop would. Counted time must come to
  1.5-2.6 s (it stands still while IP65 runs, so it falls a little
  short), and `timer_read` must follow `a2_millis` to within a few ticks
  -- IP65's own driver would instead add 33 ms per call, whatever time
  passed. `make emutest` runs it with the Uthernet2 plug-in (ReplicApple2Plus
  1.9.0's `--config` and `--plugins`) and in real time (`--real-time`), so
  the server's two seconds are real ones; unthrottled, the same delay
  would count as several times as long. `test/emutest.sh` starts the
  server (Python) and types its port at the program's prompt. The run is
  built only with `IP65=` and run only with `UTHERNET2=` (the plug-in's
  folder); otherwise it's reported as skipped. `nettest` goes on a disk
  of its own: with it, the programs come to more than one 140K disk
  holds.
  Verified with ReplicApple2Plus 1.9.0's runner, the DOS 3.3 System
  Master, and cc65 and IP65 built from their current sources: IP65's own
  `a2timer.o` stays out of the link, and `timer_read` comes from
  `a2lib-ip65.o`. All 16 runs pass; `nettest` passes all 7 checks, with
  the two seconds counted as 1,800-1,828 ms over four timed runs (IP65's
  polling, uncounted, is the other 9%) and `timer_read` one tick (4 ms)
  ahead of `a2_millis`. Unthrottled, the echo doesn't arrive within the
  10 s of counted time the program allows, and the run fails 2 of 7.
- **Differential testing:**
  - Build the same test programs for ProDOS and DOS 3.3 and compare
    results, with ProDOS as the reference for file-layer behavior.
  - For a future direct-hardware `vt` backend, compare its screens with
    the firmware backend's. The firmware's behavior comes from Videx, so
    it serves as an independent reference against shared
    misunderstandings of the spec.
- **AppleCommander** provides an independent check of what actually ends
  up on disk images.
- **sim65** (`make simtest`): cc65's 6502 simulator runs library modules
  built for its `sim6502` target, with stubs for Apple II-only imports,
  so logic and cycle counts can be checked without an Apple II (6.3).
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
  the `$0A`/`$0D` swap for ProDOS TXT files. The proposal, written after
  increment 10 and the headless test runs, is `docs/cc65-proposal.md`.
  cc65's Contributing.md asks contributors to ask whether work is wanted
  before preparing it and to keep one pull request per change, so it is
  a question with the code linked, not a pull request. It also names the
  `crt0` reordering (6.1). Posted as cc65/cc65 issue #3050
  (<https://github.com/cc65/cc65/issues/3050>), 2026-11-16.
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
| `Makefile` | Builds `lib/a2lib-dos33.lib` and the tests |

Programs link with
`cl65 -t apple2 -o prog prog.c lib/a2lib-dos33.lib`; the library is a
complete replacement for cc65's `apple2.lib` (section 2).

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
- **Zero page:** the read/write path may change `ptr1`–`ptr3`, as the
  stock path does, but must preserve `ptr4`. cc65's `fgets` keeps its
  destination pointer in `ptr4` across `fgetc` → `read`, and the stock
  read path never touches it. The first run on DOS 3.3 failed the `fgets`
  check because `rwcommon` used `ptr4` for the control block without
  saving it, so `fgets` stored characters into the control block. Fixed
  by saving `ptr4` on entry to `rwcommon` and restoring it on every exit.
  A search of cc65's `libsrc/common` found no other stdio routine that
  relies on a zero-page register surviving a call into the file layer
  (`vfscanf` uses `ptr3`, but only after its calls return).
- T-file reads and raw-file reads go byte by byte, because a range READ
  that runs into the end of the data doesn't report how many bytes it
  transferred. B-file reads use range READs clipped to the recorded
  length.

### 10.2 Confirmed on DOS 3.3

The first run of `test/filetest.c` under stock DOS 3.3 in ReplicApple2Plus
passed every T-file, B-file, `open`-flag and name check, confirming the
assumptions below, which had been taken from the sources. Each remains
isolated so it can be corrected in one place if real hardware disagrees.
The one failure (`fgets`) was a defect in this library, not in these
assumptions; see the zero-page note in 10.1.

- **Range WRITE length:** a range WRITE takes the count minus one, as
  *Beneath Apple DOS* says (`FM_WRITE_ADJUST` in `fm.inc`). Confirmed by
  the exact B-file lengths.
- **New sectors are zero-filled:** a `$00` follows the last byte written
  to a T file. Confirmed by the T read-at-end and append checks.
- **OPEN output type byte:** uses File Manager type codes, with bit 7 as
  the lock flag (masked off). Confirmed by T and B files being classified
  correctly when reopened.
- **POSITION offsets:** whole-file byte offsets when the record number
  is 0 and the file was opened with record length 0. Confirmed by append
  and by the B header's length being rewritten on close.
- **Language Card banking:** calling the File Manager with ROM banked in
  and LC bank 2 restored afterward works, the same pattern `rdkey.s`
  uses.

### 10.3 Increment 2: lseek, remove, rename, stat

| File | Role |
|---|---|
| `libsrc/dos33/lseek.s` | Replaces stock `lseek.s` (5.7) |
| `libsrc/dos33/sysremove.s` | Replaces stock `sysremove.s` (5.5a) |
| `libsrc/dos33/sysrename.s` | Replaces stock `sysrename.s` (5.5a) |
| `libsrc/dos33/stat.s` | Replaces stock `stat.s` (5.8) |
| `libsrc/dos33/fmtemp.s` | Temporary control block for DELETE and RENAME |

Changes to increment 1: the control block also keeps OPEN's type byte
(with the lock bit) and a B file's load address, for `stat`; the name
parser exports the slot and drive it resolved (`fm_slot`, `fm_drive`),
for `st_dev`.

`test/filetest.c` gains three groups (LSEEK, REMOVE/RENAME, STAT), for 50
checks in nine groups; the on-screen failure list is capped at 10 lines
so the worst case still fits 40×24.

**First run on DOS 3.3:** LSEEK and STAT passed; every REMOVE/RENAME
check failed because the linker took the stock `__sysremove` and
`__sysrename` (section 2). Fixed by building the complete library.

**Second run on DOS 3.3:** all 50 checks in nine groups passed.

### 10.4 Increment 3: directories

| File | Role |
|---|---|
| `include/dirent.h` | DOS 3.3 `struct dirent`; maps the directory functions to `_dos33_*` (section 2, 5.9) |
| `libsrc/dos33/dir.s` | `opendir`, `readdir`, `closedir`, `rewinddir` over the catalog (5.9) |
| `libsrc/dos33/rwts.s` | RWTS sector reads and error translation |

Changes to earlier increments: the name parser gains `fm_location` (for
`opendir`) and exports the volume it resolved; `stat` fills `st_blocks`
from the catalog (5.8).

Sizes: `dir.s` 542 bytes, `rwts.s` 112 bytes; `stat` grows to 362 bytes
and pulls in both.

`test/filetest.c` gains a DIRECTORY group, for 59 checks in ten groups,
and is compiled with `-I include`; the on-screen failure list is capped
at 9 lines.

**Verified by building:** the link guard was checked both ways (header
without library fails to link; with the library it links).

**First run on DOS 3.3:** all 59 checks in ten groups passed, including
the directory checks and `st_blocks` agreeing with `d_blocks`.

### 10.5 Increment 4: DOS 3.3 interrupts

| File | Role |
|---|---|
| `libsrc/dos33/irq.s` | Replaces stock `irq.s`: DOS 3.3 entry points `lcirq` and `romirq`, stock ProDOS path kept (section 6) |
| `libsrc/dos33/crt0.s` | Modified copy of stock `crt0.s`: patches the 6502 vectors before the constructors run (6.1) |
| `test/irqtest.s` | Simulated interrupts on both paths, and the test interruptor |

`test/filetest.c` gains an INTERRUPTS group, for 65 checks in eleven
groups; the on-screen failure list is capped at 8 lines.

**Verified by building:** the library's `irq.o` is the DOS 3.3 version
(segment sizes differ from stock), and the test links `initirq`,
`doneirq` and `callirq`.

**First run on DOS 3.3:** 64 of 65 passed. The LC RAM path's banking
check failed because stock `crt0` overwrote `lcirq` after the
constructors ran (6.1). Fixed with a2lib's `crt0.s`; the "installed"
flag also moved from BSS to DATA.

**Second run on DOS 3.3:** all 65 checks in eleven groups passed, so the
earlier groups also pass under the changed startup order.

**Open:** testing with real interrupts needs an IRQ source in
ReplicApple2Plus (6.2).

### 10.6 Increment 5: VideoTerm backend

| File | Role |
|---|---|
| `libsrc/vt/vt.inc`, `vt.s` | Firmware interface and core (3.5) |
| `libsrc/vt/` conio modules | Modified copies of stock `cputc.s`, `gotoxy.s`, `gotoy.s`, `clrscr.s`, `wherex.s`, `wherey.s`, `cgetc.s`, `_scrsize.s`, `cpeekc.s`, `cout.s`, `rdkey.s` |
| `test/vttest.c` | Display tests, run with and without the card |

The Makefile builds `lib/a2lib-vt.lib` alongside
`a2lib-dos33.lib`. **Verified by building:** the VideoTerm modules
replace the stock ones in the new library (larger segment sizes), the
test links them, and a stdio-only program links `vt.s` through `cout.s`.

**First run, in ReplicApple2Plus:** all 15 checks passed both with the
VideoTerm in slot 3 (80 columns) and without it (the 40-column
fallback). On the card, the cursor blinked while `cgetc` waited with
`cursor(1)`, and after exit the display returned to the 40-column screen
with a working BASIC prompt.

### 10.7 Increment 6: the 40-column window

| File | Role |
|---|---|
| `libsrc/win/win.inc`, `win.s` | The 80 × 24 buffer, window, panning and COUT hook (3.6) |
| `libsrc/win/` conio modules | `cputc.s`, `gotoxy.s`, `gotoy.s`, `clrscr.s`, `wherex.s`, `wherey.s`, `cgetc.s`, `_scrsize.s`, `cpeekc.s`, `cout.s`, `rdkey.s`, each with the VideoTerm path and the window path |
| `include/c40win.h` | `c40_pan`, `c40_follow`, `c40_left`, `c40_active` |
| `test/vttest.c` | Also built as `wintest` (with `C40WIN`), adding scrolling and panning checks |

The Makefile builds `lib/a2lib-c40win.lib`.

**First run, in ReplicApple2Plus:** all four combinations passed:
`wintest` without the card (40-column window, 20 checks) and with it
(VideoTerm, 16), and `vttest` with the card (16) and without it (stock
40-column screen, 15). In the window, the caret flashed while `cgetc`
waited, and after exit the BASIC prompt appeared below the program's
output.

### 10.8 Increment 7: cooperative timer, software clock, gauge

| File | Role |
|---|---|
| `libsrc/dos33/timer.inc`, `timer.s` | Tick counting, slots, dispatcher, API, `KSW` input routine (6.3) |
| `libsrc/dos33/tick.s` | The hook vector the wait loops call |
| `libsrc/dos33/cgetc.s`, `kbhit.s` | Modified copies of stock modules: tick hook; `kbhit` waits one tick while the timer is in use |
| `libsrc/dos33/gettime.s`, `settime.s` | Modified copies of stock modules: software clock under DOS 3.3, stock code under ProDOS; `a2_clock_age` |
| `libsrc/vt/cgetc.s`, `libsrc/win/cgetc.s` | Tick hook in their wait loops |
| `libsrc/win/win.s` | Position gauge (6.3) |
| `libsrc/ip65/a2timer.s` | IP65 timer driver, built as `lib/a2lib-ip65.o` |
| `include/a2timer.h` | Public API |
| `test/timertest.c`, `test/timerzp.s` | Emulator tests (ticks, timers, zero page, clock, stdio input) |
| `test/sim/` | sim65 regression tests (`make simtest`) |

`test/vttest.c` gains two gauge checks in its window build.

**Verified:** `make simtest` passes (all timer and gauge checks); the
IP65 object links ahead of IP65's Uthernet II driver library, which
then doesn't contribute its own `a2timer.o` (checked with a link map of
a program calling `ip65_init` and `ip65_process`).

**First run on DOS 3.3, in ReplicApple2Plus:** `wintest` passed all 22
checks without the card, including the gauge appearing after a pan and
disappearing after a second of counted time. `timertest` passed 17 of
19: TICKS, TIMERS and CLOCK passed; the INPUT group's callback and
counted-time checks failed because DOS replaced the `KSW` routine (6.3,
"Installing the input routine under DOS 3.3"). Fixed by installing it as
DOS's true input routine when DOS's intercept is in `KSW`.

**Second run on DOS 3.3:** `timertest` passed all 19 checks, including
callbacks and counted time during stdio input.

**DOS and `CSW` (after increment 7):** `test/cswtest.c`, built as
`cswtest` (VideoTerm library) and `cswwtest` (window library), checks
that output through the monitor's `COUT` reaches the backend before and
after stdio input. The first run (VideoTerm) failed after input, as the
mechanism predicted; `vt.s` and `win.s` now install as DOS's true output
routine (3.5).

**Second run, in ReplicApple2Plus under DOS 3.3:** `cswtest` with the
VideoTerm and `cswwtest` without it both passed, with DOS's intercept
staying in `CSW` (`$9EBD`) and the backend's routine as DOS's true output
handler before and after input. As regression checks, `vttest` (with the
card, 16 checks) and `wintest` (without it, 22 checks) passed too.

### 10.10 Increment 8: reflow filter

| File | Role |
|---|---|
| `libsrc/dos33/reflow.s` | The filter, `reflow_on`, `reflow_off` (3.7) |
| `libsrc/dos33/cout.s` | Modified copy of stock `cout.s`: `COUT` as a vector |
| `libsrc/vt/cout.s`, `libsrc/win/cout.s` | The same vector in the other libraries |
| `libsrc/{dos33,vt,win}/viewport.s` | Visible width for each library |
| `include/a2reflow.h` | Public API |
| `test/reflowtest.c` | Emulator test, built as `reflowtest`, `reflowvt`, `reflowwin` |
| `test/sim/reflowsim.c`, `reflowshim.s` | sim65 regression test |

**Verified:** `make simtest` passes all reflow cases.

**First run, in ReplicApple2Plus under DOS 3.3:** all three builds
passed: `reflowtest` on the stock screen (`W=40`, 6 checks), `reflowvt`
on the VideoTerm (`W=80`, 6), and `reflowwin` in the 40-column window
(`W=40`, 7, including that the window didn't pan).

### 10.11 Next increments

- Monochrome monitor setting in ReplicApple2Plus (3.8): done, in that
  project, with the half-pixel shift
- Display backends: Soft-70 (3.8): increment 9, 10.12
- Emulator test fixture (section 8): done. ReplicApple2Plus 1.8.0's
  headless runner and `make emutest`; with 1.9.0's slot configurations,
  plug-ins and real-time pacing, the network run on the Uthernet II
- Detect deleting or renaming an open file, as ProDOS does (5.5a): done,
  10.13

### 10.12 Increment 9: shared 80 × 24 model, Soft-70

| File | Role |
|---|---|
| `libsrc/s80/s80.s`, `s80.inc` | The shared 80 × 24 model (from `win.s`) |
| `libsrc/s80/*.s` | Conio modules shared by the window and Soft-70 (moved from `libsrc/win/`) |
| `libsrc/win/win.s`, `display.inc` | The window's display |
| `libsrc/s70/s70.s`, `display.inc` | Soft-70's display, `s70_font` |
| `libsrc/s70/cgetc.s`, `rdkey.s` | Soft-70's cursor while waiting |
| `libsrc/s70/font.s` | Default font, generated |
| `tools/s70font.txt`, `s70font.py` | Font source and tool |
| `include/soft70.h` | Public API |
| `lib/a2lib-soft70.lib` | VideoTerm, or Soft-70 without one |
| `test/vttest.c`, `reflowtest.c`, `cswtest.c` | Emulator tests, also built as `s70test`, `reflows70`, `cswstest` |
| `test/sim/s70sim.c`, `s70shim.s`, `sim4000.cfg` | sim65 regression test |
| `test/sim/bssfill.s`, `gaugesim.c` | Check that startup leaves a BSS buffer to `crt0` |
| `libsrc/s80/s80.s` (marker), `s70sim.c` | Text marker (3.9) and its check |

**Verified, refactoring.** A differential sim65 run of the window before
and after the extraction: 3,000 random conio operations (characters,
controls, cursor moves, inverse, pans, follow, clears, timer ticks), with
the text screen, cursor, pan position and `cpeekc` compared after every
one, gave identical results. The existing suites (`gaugesim` and the
others) pass.

**Verified, Soft-70 (`s70sim`).** The hi-res page is checked against a
rendering of the model's buffer with the font in use: every cell phase
in normal, inverse and flashing video; both nibbles of a merged font;
then 4,000 random operations (as above, plus font changes and the
blinking cursor shown and removed), checked every 40; a full scroll; a
pan; the gauge shown after a pan and gone after a second; bit 7 clear
throughout. Two deliberate faults (scroll extents, the bar in cells on
row 23) were each caught. `s70test` checks on the emulator that a
letter drawn at two bit offsets shows the same pixels, inverse, the
gauge's bar and panning.

**First emulator run: `wintest` stopped in the monitor (BRK at `$2D82`).**
Diagnosed from the link map: the address is in `ONCE`, in the model's
constructor, just after it cleared the buffer. `apple2.cfg` starts BSS
where `ONCE` starts (BSS is cleared after the constructors run, 6.1), so
clearing the window's buffer, which is in BSS, overwrote the running
constructor. Before the extraction the window never cleared its buffer at
startup; the clear was added for Soft-70, whose buffer is in `LOWBSS`.
Fix: the constructor clears the buffer only when it is outside BSS
(`S80_BUFSEG`), and leaves a BSS buffer to `crt0`. sim65 missed it because
its `crt0` clears BSS before the constructors run and its configs don't
overlap `ONCE` and BSS; `gaugesim` now checks it directly (a constructor
run before the model's marks the buffer, `test/sim/bssfill.s`, and the
mark must survive startup). The check failed before the fix and passes
after it.

**Emulator runs, ReplicApple2Plus under DOS 3.3 (after the fix above).**
All passed:

- Without the VideoTerm, the window on the shared model: `wintest` (22
  checks), `reflowwin` (7, no pan) and `cswwtest` (both, with `s80_cout`
  as DOS's true output routine), as in increments 6-8.
- Without the VideoTerm, Soft-70 on a monochrome monitor: `s70test` (23),
  `reflows70` (7, `W=70`, no pan) and `cswstest` (both; stdio input
  through `rdkey`).
- With the VideoTerm: `s70test` on the card (16).

Two test faults were found and fixed on the way, neither in the library:
`s70test`'s inverse check read `cpeekc` at the cursor, which had moved
past the cell it wrote (it now reads that cell), and `reflows70`'s
heading said "WINDOW". The emulator run also showed the underscore
(bottom scanline) touching the capitals of the line below; it stays
there, as in the period fonts (decision).

### 10.13 Increment 10: open files can't be deleted or renamed

| File | Change |
|---|---|
| `libsrc/dos33/fmtemp.s` | `fm_isopen`: whether a named file is open |
| `libsrc/dos33/fm.inc` | Declares `fm_isopen` |
| `libsrc/dos33/sysremove.s`, `sysrename.s` | Refuse an open file with `$50` (`EINVAL`) |
| `test/filetest.c` | Three checks in REMOVE, RENAME |

**Verified with `make emutest`** (ReplicApple2Plus 1.8.0's runner, DOS 3.3
System Master). The new checks were run first against the unchanged
library and failed ("remove open file", and "remove after close", since
the open file had been deleted); with the change, `filetest` passes all 68
checks, and the other 14 runs still pass.

### 10.14 Increment 11: exec()

| File | Change |
|---|---|
| `libsrc/dos33/exec.s` | New: `exec()` under DOS 3.3, BRUN or RUN through COUT (5.10) |
| `libsrc/dos33/mainargs.s` | Modified copy: takes exec()'s arguments from page 2 |
| `libsrc/dos33/VENDORED.md` | Lists `mainargs.s`; notes `exec.s` |
| `test/exectest.c`, `test/argtest.c` | Three runs: `exectest`, `exectest-vt`, `execatest` |
| `test/bloadprobe.c`, `test/errprobe.c`, `test/errstub.s` | The probes run before implementation (5.10) |
| `test/emutest.sh` | The exec disk; pass conditions joined with ` && `, `!` to negate |

Raised by polluks on cc65/cc65#3050. **Verified with `make emutest`:** all
22 runs pass (5.10).

### 10.15 Increment 12: DOS 3.3 error numbers

| File | Change |
|---|---|
| `libsrc/dos33/oserror.s`, `oserrlist.s` | New: replace the stock ProDOS tables with DOS 3.3's numbers and messages, plus the library's codes (5.6) |
| `libsrc/dos33/fm.inc` | `DOSERR_*` and `LIBERR_*` |
| `libsrc/dos33/fm.s`, `rwts.s` | `fm_maperr` passes DOS's numbers through; `rwts_maperr` gives DOS's numbers |
| `dir.s`, `exec.s`, `fmname.s`, `fmtemp.s`, `lseek.s`, `open.s`, `seekend.s`, `sysremove.s`, `sysrename.s` | DOS or library codes in place of ProDOS codes |
| `test/filetest.c` | `__oserror` checked with `errno`; `_stroserror` for one DOS and one library code |
| `DESIGN.md` | Guiding principle revised (cc65/cc65#3050); 5.6 rewritten |

`errno` values are unchanged, so only `__oserror` and `_stroserror`
differ for programs.

### 10.16 Readability pass: the DOS 3.3 file layer

Names and comments only: every module assembles to the same bytes, and
every test program links to the same binary, as before the pass (checked
against `732448c`: 230 module builds, 65 compiled test variants, 23
programs, and the sim65 suites).

| File | Change |
|---|---|
| `libsrc/dos33/machine.inc` | New: names for the language-card switches, `MON_COUT`, `DOS_CONNECT`, the stack page and `BASIC_BUF`, and high-bit characters, beside cc65's `apple2.inc` |
| `libsrc/dos33/fm.inc` | Includes `machine.inc`; names for the IOB's values and RWTS's codes, the lock bit and type mask, and `NAME_LEN`; `FMR_ENDDATA` and `FMR_NOTFOUND` folded into `DOSERR_*` |
| `exec.s`, `fm.s`, `rwts.s`, `timer.s`, `reflow.s`, `dir.s`, `fmname.s`, `stat.s`, `open.s`, `rwcommon.s`, `lseek.s`, `seekend.s`, `sysremove.s`, `sysrename.s` | Those names in place of raw values; named labels in place of anonymous jumps two levels away; stale comments about ProDOS codes corrected |

Vendored modules (`VENDORED.md`) keep their stock code untouched, so they
stay easy to compare with cc65's.

### 10.17 Readability pass: the display backends

Names and comments only, checked the same way as 10.16: identical bytes
for every module (each backend's flags, and `sim6502`) and every program.

| File | Change |
|---|---|
| `libsrc/s80/s80.inc` | `S80_BUF_XOR`: the buffer holds screen codes XOR `$A0`, so a blank is `$00` |
| `libsrc/s80/s80.s`, `libsrc/win/win.s`, `libsrc/s70/s70.s` | `S80_BUF_XOR` in place of `eor #$A0`; named labels for nested loops (row and column) and other two-level jumps |
| `libsrc/win/win.s` | `TEXT_PAGE1` for the text screen's `$0400` |
| `libsrc/s70/s70.s` | `SCANLINE` for the `$0400` step between a text row's scanlines; `BARLINE` from `ROW23` |
| `libsrc/vt/vt.s` | `vtdone`'s branches name `mode` instead of an anonymous label just before it |

The backends' modules based on stock ones (`cgetc.s`, `rdkey.s`,
`cout.s` and the like) keep their stock code; `s70/font.s` is generated
from `tools/s70font.txt`.

### 10.18 Readability pass: tests and tooling

No change in what anything does, checked by what each file produces:
the C tests compile to the same assembly; `make -n` gives the same
commands for every target; and `test/emutest.sh`, run against stand-ins
for the runner and AppleCommander, makes the same calls and exits the same
way in six cases (every run, named runs, a VideoTerm run, the network run
with and without `UTHERNET2`, and an unknown name).

| File | Change |
|---|---|
| `test/emutest.sh` | The exec disk's names: `EXEC_DISK`, `EXEC_PROGS`, `EXEC_EXTRA`, `on_exec_disk` (they hold the exec tests, not only the probes); the card field read into `card`, not `vt`; the run format described field by field |
| `Makefile` | Comments only: the header lists every target and the Soft-70 library; the sim65 comment names all four suites |

`tools/emutest.sh`, the original runner script, which nothing had used
since `test/emutest.sh` replaced it, was removed afterwards (`aba82d7`).

### 10.19 Increment 13: DOS 3.3 file types

| File | Change |
|---|---|
| `include/dos33_filetype.h` | New: `DOS33_T_*` (the catalog's codes) and `DOS33_LOCKED` |
| `include/dirent.h` | `d_type` holds DOS 3.3's type; `d_access` the lock bit; `d_dostype` removed; includes `dos33_filetype.h` |
| `libsrc/dos33/fm.inc` | `FMT_SPECIAL`; `FMT_RELOC` corrected from `$08` (S) to `$10` (R): one coding for OPEN and the catalog (4.4) |
| `libsrc/dos33/open.s` | `_filetype` in DOS 3.3's codes (T, I, A, B, S, R), default B; the "new" A and B fail with `EINVAL` |
| `libsrc/dos33/stat.s`, `dir.s` | `st_type`/`d_type` in DOS 3.3's codes, `st_access`/`d_access` the lock bit; the ProDOS translation tables removed |
| `test/filetest.c`, `test/exectest.c` | `DOS33_T_*`; new checks: an R file created and reported as R by `stat` and `readdir`, and the "new" A type refused |
| `README.md`, `docs/cc65-proposal.md` | README brought up to date (types, and errors since increment 12); a note on what the posted proposal no longer describes |

Raised by Oliver Schmidt's review on cc65/cc65#3050 ("as if there were no
ProDOS library yet").

**Found on the emulator:** the first version followed 4.4 as it stood,
converting between two codings for S and R. Its R check failed in
`readdir` (`stat` passed, since it converted OPEN's byte back). DOS's own
code (ch. 8) shows one coding, so the conversion went, 4.4 was corrected,
and `FMT_RELOC` was fixed: a bug since increment 1, found because this
increment added the first R file test.

### 10.20 Code conventions and tools/samebytes.sh

| File | Change |
|---|---|
| `DESIGN.md` | Section 1, "Code conventions": the rules the readability passes applied, for every change |
| `tools/samebytes.sh` | New: the byte-identity check used for 10.16 to 10.18, so any change can be checked the same way |
| `libsrc/s80/s80.s` | `HI_CR`, `HI_LF`, `HI_BS`, `HI_SPACE` for the output handler's characters (missed in 10.17) |
| `libsrc/dos33/mainargs.s` | `HI_CTRL_D`, `HI_CR`, `HI_SPACE` in `execargs`, a2lib's addition (from increment 11); stock code unchanged |
| `libsrc/dos33/machine.inc` | `HI_LF`; `BASIC_BUF` defined only if not already (stock `mainargs.s` defines it) |

Found by auditing increments 11 to 13 against the conventions. Verified
with `tools/samebytes.sh` against `7a11bbe`: identical. The tool itself
was checked the other way too: a one-byte change in `s80.s` was reported
in all seven programs that link it, with exit status 1.

### 10.21 Increment 14: POSIX paths

| File | Change |
|---|---|
| `libsrc/dos33/fmname.s` | Rewritten: `/S/D/NAME`, `D/NAME`, `NAME`; directories `/S/D`, `D`, `.`; no suffixes, no sticky defaults, no volume; commas allowed in names |
| `libsrc/dos33/syschdir.s` | New: `chdir` sets DOS's last-used slot and drive |
| `libsrc/dos33/initcwd.s` | New (modified copy): `__cwd` is `"/S/D"` under DOS 3.3, so `getcwd` works |
| `libsrc/dos33/sysrename.s` | The new path must be at the old one's slot and drive |
| `libsrc/dos33/exec.s` | No volume suffix (`putdec` gone); a name with a comma fails with `EINVAL`; stub 115 bytes at `$35D` |
| `libsrc/dos33/dir.s`, `include/dirent.h` | `opendir` takes directory paths |
| `libsrc/dos33/VENDORED.md` | Lists `initcwd.s` |
| `test/filetest.c` | New group PATHS (10 checks: absolute, drive and `./` paths; bad drive; `getcwd`; `chdir` there and back; `chdir` to a non-directory; a comma in a name; `opendir` of a drive); paths in place of suffixes elsewhere |
| `test/exectest.c`, `test/argtest.c` | Paths for exec's names; a fifth pre-exec check: a name with a comma |
| `README.md`, `docs/cc65-proposal.md` | Paths |

Raised by Oliver Schmidt's review on cc65/cc65#3050. The parser was run in
a 6502 simulator (py65) before the emulator, on 42 paths for `fm_name` and
`fm_location`: every valid form, and malformed ones (slot 0 or 8, drive 3,
`/6`, `/`, a missing name, a slash in a name, 31 characters, a name with a
leading digit), each giving SYNTAX ERROR. All passed.

### 10.22 DOS 3.3 only

| File | Change |
|---|---|
| `libsrc/dos33/crt0.s` | No ProDOS check or quit path: the C stack is below HIMEM, and the 6502 vectors are always patched |
| `libsrc/dos33/irq.s` | No ProDOS interrupt allocation or its error message |
| `libsrc/dos33/initcwd.s`, `gettime.s`, `settime.s` | DOS 3.3 code only |
| `libsrc/dos33/mainargs.s` | argv[0] is always `""`, kept out of page 2; no ProDOS file name |
| `libsrc/dos33/dir.s`, `exec.s`, `open.s`, `sysremove.s`, `sysrename.s`, `syschdir.s` | No `__dos_type` guard |
| `libsrc/dos33/timer.s`, `libsrc/vt/vt.s`, `libsrc/s80/s80.s` | No `__dos_type` test before DOS's I/O hooks |
| `libsrc/dos33/fm.inc`, `oserror.s`, `oserrlist.s`, `test/filetest.c` | `LIBERR_NODOS` removed; the codes after it renumbered (5.6) |
| `libsrc/dos33/machine.inc` | `BASIC_BUF` unconditional (mainargs.s no longer defines it) |
| `test/sim/shim.s` | Stand-ins for `__dos_type`, `callmli` and `_mktime_dt` removed |
| `VENDORED.md`, `README.md`, `include/a2timer.h`, DESIGN 1, 5.6, 5.10, 6.1 | DOS 3.3 only |

Raised by Colin Leroy-Mira's review on cc65/cc65#3050. The modules shrink
by 461 bytes in all (od65 segment sizes, BSS excluded); a linked program
by 50 to 85 bytes, `filetest` by 259, and `timertest` by 1254, because
`gettime.s` no longer pulls in ProDOS's date conversion. `mli.o`, with
`callmli` and `dosdetect.o`, is still linked through `mliparam`, which
`rwcommon.s` and stock `read.s` share.

### 10.23 DOS's file buffers for control blocks

| File | Change |
|---|---|
| `libsrc/dos33/fmbuf.s` | Was `fmtemp.s`: `fm_getfcb` reserves a free DOS buffer (in place of `malloc`), `fm_freefcb` releases it |
| `libsrc/dos33/fm.inc` | `FCB` is a DOS buffer, addressed at its work area, with the library's fields in the name field; `DOS_BUFS` |
| `libsrc/dos33/fm.s` | `fm_begin` points the parameter list at the work area and the two pages below it |
| `libsrc/dos33/open.s` | `open` reserves its control block with `fm_getfcb` (`ENOMEM`, `__oserror` `$0C` when none is free); `freebuffer` skips the console; `closeallfiles` releases the buffers |
| `libsrc/dos33/exec.s`, `sysremove.s`, `sysrename.s` | `fm_getfcb` |
| `test/filetest.c` | New group DOS BUFFERS (6 checks: all free at start; one used per open file; one more `open`, and `remove`, fail with `ENOMEM` when none is free; `close` frees them; the files are removed); MAX_SHOWN 6 |

Raised by Colin Leroy-Mira's review on cc65/cc65#3050: `malloc` and
`free` cost 739 bytes. `exectest` shrinks by 746 bytes; other programs
that open files lose `malloc` unless they use it themselves (`opendir`
does, as stock's does). `fm_getfcb` was run on sim65 against a built
chain of three buffers, the second in use: it skips the used one, clears
the 11 library bytes and nothing past them, fails with `$0C` when all are
taken, and reuses a released buffer.

### 10.24 Console-only programs leave the file code out

| File | Change |
|---|---|
| `libsrc/dos33/rwcommon.s` | Now only `rwprolog`, `rwepilog`, the byte count `rw_count`, and `rwcommon`: a `JMP` that `rwfile.s`'s constructor points at the file code |
| `libsrc/dos33/rwfile.s` | Was `rwcommon.s`'s file code; also moves to the end of an `O_APPEND` file before a write (`seekend`) |
| `libsrc/dos33/write.s` | Stock's without the `O_APPEND` path; the device count goes to `rw_count` |
| `libsrc/dos33/open.s` | `.forceimport rwfile` |
| `libsrc/dos33/VENDORED.md` | `write.s`, `mli.inc` |

Found while measuring 10.23: stock `write.s` reaches `rwcommon` and
`seekend` directly, so every program that used `printf` linked the whole
file layer (`rwcommon`, `seekend`, `fm.s`) and, through `mliparam`,
ProDOS's `mli.o` and `dosdetect.o`. Only `open` creates file
descriptors, so the file code is linked with it. Programs that don't
open files shrink by 1075 bytes (argtest, timertest, the display and
reflow tests); those that do, by 25. No test program links `mli.o` or
`dosdetect.o` now. The `O_APPEND` tests (T and B files, filetest) cover
the moved path.

### 10.25 Size pass: the file layer, first round

| File | Change |
|---|---|
| `libsrc/dos33/exec.s` | The command is built from a template (`",S0,D0"` and CR, digits patched in) copied by the loop that copies the verb; the name is copied and trimmed in one pass |
| `libsrc/dos33/fm.s` | `fm_open` (OPEN with variable-length records; A = type for a new file), `fm_op`; `fm_fdfcb` and `fm_fdbegin` load a slot's control block (and begin) |
| `libsrc/dos33/open.s`, `fmbuf.s`, `sysrename.s`, `exec.s` | `fm_open` in place of four copies of the OPEN setup |
| `libsrc/dos33/open.s`, `lseek.s`, `seekend.s`, `stat.s` | `fm_fdfcb`/`fm_fdbegin` in place of five copies of the load |

Raised by Colin Leroy-Mira's review on cc65/cc65#3050, whose example was
`exec.s`'s character-by-character suffix. The modules shrink by 91 bytes
(od65): `exec.o` by 29, `open.o` by 36. No behavior changes; `make
emutest` covers every path touched (exectest's commands, filetest's
OPEN, lseek, O_APPEND and stat groups).

### 10.26 Link-time guards for functions with no DOS 3.3 version

| File | Change |
|---|---|
| `libsrc/guard/*.s` | New: one guard per stock module (`curdevice`, `devicedir`, `getdevice`, `dioopen`, `dioclose`, `dioread`, `diowrite`, `diosectcount`, `diosectsize`, `file_set_info`, `statvfs`, `sysmkdir`, `sysrmdir`, `getres`), replacing it in `a2lib-dos33.lib` (4.2) |
| `Makefile` | Builds the guards into `a2lib-dos33.lib` (and so into the backend libraries); `make linktest` |
| `test/linktest.sh` | New: a program per guarded function must fail to link, naming its guard symbol; a control program using `fopen`, `remove`, `rename`, `chdir` and `clock_gettime` must link |
| `DESIGN.md` | 4.2: link-time failure replaces run-time `ENOSYS` |

Before this change, these functions failed at run time: `callmli` returns
`$01` when `__dos_type` is 0 (mapped to `ENOSYS`), `getres` returns
`ENOSYS`, and the device functions return `INVALID_DEVICE` (or, for
`getdevicedir`, NULL). Two did worse:
`dio_query_sectsize` returned ProDOS's 512, and `rmdir` deleted the file
it named, because stock `sysrmdir.s` aliases `_sysremove`, which a2lib
replaces with DOS 3.3's DELETE (confirmed with a link map: `rmdir` linked
a2lib's `sysremove.o`).

Verified: `make linktest` passes (16 guards, control links). Run against
the previous library (the stock modules put back with `ar65 r`), all 16
checks fail and the control links. `make test` builds every test program
unchanged; `make simtest` passes. `clock_getres`'s guard goes when the
software clock gets its own `clock_getres`.

### 10.27 rename of a locked file; stat and errno

| File | Change |
|---|---|
| `libsrc/dos33/sysrename.s` | A RENAME error goes through `fm_maperr`; it fell into the syntax-error path, so every RENAME failure gave `EINVAL` |
| `libsrc/dos33/stat.s` | Puts the caller's `errno` back on success; it was left 0 |
| `test/filetest.c` | REMOVE, RENAME: a locked file can't be removed or renamed (`EACCES`); the file is locked and unlocked with DOS's LOCK and UNLOCK, sent through COUT (`dos_cmd`, which puts the cursor back so the screen keeps its rows). STAT: a successful `stat` keeps `errno`. `MAX_GROUP` 13 |
| `test/cswcout.s` | Comment: the tests that use it |
| `Makefile` | `filetest` links `test/cswcout.s` |
| `DESIGN.md` | 5.5a, 5.8 |

Found by a line-by-line review of the library. Both failures were shown
before the fixes: `make emutest` (filetest) failed 2 of 92 checks,
"RENAME LOCKED EACCES" and "STAT KEEPS ERRNO"; "RENAME LOCKED FAILS"
passed, so DOS's RENAME does refuse a locked file. `stat.o` grows by 29
bytes, `sysrename.o` by 2.

### 10.28 Console write of a multiple of 256

| File | Change |
|---|---|
| `libsrc/dos33/write.s` | The device loop adds one to the count's high byte when the low byte is nonzero, then counts down to 0 (`bne`, not `bpl`) |
| `libsrc/dos33/VENDORED.md` | The fix, as a difference from stock |
| `test/coutcount.s` | New: counts what console output sends through CSW, without showing it |
| `test/filetest.c` | STDIO: `write` to stdout of 255 and 257 characters, and of 256 and 512, sends exactly that many through COUT |
| `Makefile` | `filetest` links `test/coutcount.s` |

The device loop (stock `libsrc/apple2/write.s`, still in cc65 at
`eebf54a`; `libsrc/agat/write.s` has the same loop) counted down with
`dex / bne / dec high / bpl`. With a low byte of 0, the first pass ran
256 times and the next one ran again in full, so a count of 256 sent 512
characters and 512 sent 768, the extra ones read from past the buffer.
Found by the line-by-line review and shown in sim65 (the loop extracted
unchanged) before the test existed. Shown on DOS 3.3 before the fix:
`make emutest` (filetest) failed 1 of 94 checks, "CONSOLE WRITE 256,
512". The fixed loop was checked in sim65 for every count from 0 to 2048
and for 65535. `write.o` grows by 8 bytes.

### 10.29 A disk write-protected while a file is open

| File | Change |
|---|---|
| `test/wptest.c` | New: `close` on a disk protected after appending to a B file fails with `EACCES` and keeps the file open; made writable, a second `close` saves all 8 bytes (5.11) |
| `test/emutest.sh` | The `wptest` run, on the exec disk, with the runner's `--protect` and `--writable` steps |
| `Makefile` | Builds `wptest` |
| `DESIGN.md` | 5.11 |

Raised by the line-by-line review, which asked whether a failed `close`
leaves the fd open on a file DOS has closed. ReplicApple2Plus's runner
gained `--protect` and `--writable` for it. Verified: `make emutest`
(wptest) passes, 5 of 5, with no library change; the case the review
raised can't be produced this way (5.11).

### 10.30 POSIX: rename to the same name; O_CREAT on an existing file

| File | Change |
|---|---|
| `libsrc/dos33/sysrename.s` | After the open-file check, a new name equal to the old one returns 0 without RENAME; it failed with `EEXIST` |
| `libsrc/dos33/open.s` | With `O_CREAT` and a `_filetype` the File Manager doesn't create, OPEN without allocating: an existing file opens (`O_EXCL` still gives `EEXIST`), a missing one fails with `EINVAL` as before; it failed with `EINVAL` either way |
| `test/filetest.c` | OPEN FLAGS, NAMES: an existing file opens with `O_CREAT` and a type DOS can't create. REMOVE, RENAME: a file renamed to its own name is left as it is. `MAX_GROUP` 14 |
| `DESIGN.md` | 5.4, 5.5a |

Found by the line-by-line review. Shown before the fixes: `make emutest`
(filetest) failed 2 of 96 checks, "O_CREAT EXISTING, ANY TYPE" and
"RENAME TO OWN NAME". `open.o` grows by 11 bytes, `sysrename.o` by 17.

### 10.31 Add-on libraries and selectors

| File | Change |
|---|---|
| `libsrc/timer/` | Moved from `libsrc/dos33/`: `timer.s`, `timer.inc`, `tick.s`, `gettime.s`, `settime.s`, `cgetc.s`, `kbhit.s`; `VENDORED.md` for `cgetc.s` and `kbhit.s` |
| `libsrc/reflow/` | Moved from `libsrc/dos33/`: `reflow.s`, `cout.s`, `viewport.s`; `VENDORED.md` for `cout.s` |
| `libsrc/select/*.s` | New: a selector for each add-on (2) |
| `libsrc/guard/gettime.s`, `settime.s` | New: guards for the clock in the core (4.2) |
| `libsrc/dos33/VENDORED.md` | The moved modules' notes go with them |
| `Makefile` | Builds `a2lib-timer.lib`, `a2lib-reflow.lib`, the display libraries without a copy of the core, and the selectors; each test links its add-ons; `make linktest` builds everything first |
| `test/linktest.sh` | Takes the library folder. Guards: `clock_gettime`, `clock_settime`, `time`. Controls: the file functions alone, and the clock with the timer. Programs reaching each add-on only through stock modules get its modules (link maps) |
| `test/selcheck.py` | New: each selector pulls in exactly what modules listed after it may import; parity of replacing modules (2) |
| `README.md`, `include/*.h`, `libsrc/ip65/a2timer.s`, test headers | The libraries' new names and link lines |
| `DESIGN.md` | 2, 3.5, 3.6, 4.2 |

The library files are renamed: `apple2-dos33.lib` is now
`a2lib-dos33.lib`, and `apple2-dos33-vt.lib`, `-vtwin.lib` and
`-vts70.lib` are `a2lib-vt.lib`, `a2lib-c40win.lib` and
`a2lib-soft70.lib`. Earlier records use the new names too, so they can be
followed in the current tree.

The display libraries now include `kbhit.s` from the timer. The combined
libraries had it, through their copy of the core, and without it a
program polling `kbhit` in the 40-column window or on Soft-70 would stop
running the timers their gauge and cursor use.

Verified: `make emutest` passes, all 22 runs (`nettest` not built), and
`make linktest`, 53 checks. `test/selcheck.py` was shown
to fail for a selector missing `RDKEY`, for one with `_cpeekc` added,
and for a VideoTerm `cputc.s` that didn't export `cputdirect`. `make
simtest` passes. Every test program links the same modules as before,
with these differences (sizes against the previous build):

| Programs | Bytes | Why |
|---|---|---|
| Core only (`filetest`, `exectest`, `wptest` and the probes) | -3 to -11 | Stock `cout.s` in place of the vector; no `tick.s` with stock `cgetc` |
| `reflowtest` | -8 | No `tick.s` |
| `vttest`, `wintest`, `s70test` | +78 to +108 | `kbhit.s`, `rdkey.s`, `viewport.s` forced |
| `reflowvt`, `reflowwin`, `reflows70` | +87 to +227 | The same, and `cputc.s` and `wherey.s` |
| `cswtest`, `cswwtest`, `cswstest` | +119 to +200 | The same, and `_scrsize.s`, `wherex.s` |
| `timertest` | +266 | The timer's `cgetc.s`, with the stock `cputc.s` and `gotoxy.s` it calls for the cursor |
| `exectestvt` | +556 | The VideoTerm's conio modules, none of which it calls |

### 10.32 Copies of stock modules in the add-ons; a missing selector fails to link

| File | Change |
|---|---|
| `tools/stockcopy.py` | New: adds to an add-on copies of the core modules that call into it (2) |
| `tools/libobj.py` | New: reads objects and libraries with `od65` and `ar65`, for `stockcopy.py` and `selcheck.py` |
| `Makefile` | Each add-on library gets its copies when built; `PYTHON` |
| `libsrc/select/*.s` | Display selectors: `COUT`, `RDKEY`, `_wherex`, `a2_viewport`, and define `a2lib_display_needs_selector_object`. Timer: nothing. Reflow: `COUT` |
| `libsrc/vt/vt.s` | Imports `a2lib_display_needs_selector_object` |
| `test/selcheck.py` | A module copied into the add-on needs no forcing; uses `tools/libobj.py` |
| `test/linktest.sh` | Programs calling only `cputs`, `cgets`, `cprintf`, `printf`, `time` get the add-on's modules; a display library without its selector, and two display libraries, fail to link; the VideoTerm library ahead of the timer library supplies `cgets` and `cgetc` |
| `README.md`, `DESIGN.md` | 2 |

In 10.31, a selector forced in every module of its add-on that a core
module may import, so a program paid for the display's `cputc`, `cgetc`
and `gotoxy` though it called none of them, up to 556 bytes. With the
callers copied, those are taken only when the program reaches them.
Measured as the RAM a program occupies (image and BSS, from the link
maps; zero page unchanged), against the build before 10.31:

| Program | 10.31 | 10.32 |
|---|---|---|
| Core only (`filetest`, `exectest`, `wptest`, the probes) | -3 to -11 | -3 to -11 |
| `reflowtest` | -8 | -8 |
| `timertest` | +266 | -3 |
| `exectestvt` | +556 | +45 |
| `cswtest`, `cswwtest`, `cswstest` | +119 to +200 | +30 to +45 |
| `vttest`, `wintest`, `s70test` | +78 to +108 | +42 to +72 |
| `reflowvt`, `reflowwin`, `reflows70` | +87 to +227 | +32 to +62 |

What remains is the selector's `rdkey.s`, `viewport.s` and `wherex.s`,
and `cout.s` where the program doesn't print.

Verified: `make emutest` passes, all 23 runs (`nettest` included), and
`make linktest`, 82 checks. `test/selcheck.py` was shown to fail for a
VideoTerm library without its copy of `cputs` (the
selector would have to pull in `cputc` and `gotoxy`), and for a selector
without `RDKEY` and with `_cpeekc`. `make simtest` passes.

### 10.33 Directory modules under cc65's names; guards for cc65's dirent.h

| File | Change |
|---|---|
| `libsrc/dos33/opendir.s`, `readdir.s`, `closedir.s`, `rewinddir.s` | New, from `dir.s` (removed), as in cc65's `libsrc/apple2`: `opendir.s` holds `dir_at` and `read_dir_sector_ptr1`, as stock's holds `read_dir_block_ptr1`; `rewinddir.s` exports `rewinddir_ptr1`, as stock `closedir.s` exports `closedir_ptr1`. NULL and 0 are returned through the runtime's `return0`, as in stock |
| `libsrc/dos33/dir.inc` | New, as stock's: the catalog's layout and `DIR` and `DIRENT`, from `fm.inc` |
| `include/dirent.h`, `libsrc/dos33/stat.s` | `_opendir_a2lib` and the like in place of `_dos33_opendir` |
| `libsrc/guard/opendir_stock.s`, `readdir_stock.s`, `closedir_stock.s`, `rewinddir_stock.s` | New: guards under the stock names (2) |
| `libsrc/guard/dir_entry_count.s` | New: guard (4.2) |
| `test/linktest.sh` | The four functions compiled with cc65's `dirent.h`, and `dir_entry_count`, must fail to link; the control program calls the directory functions. `link` takes `stock` to compile without a2lib's headers |
| `tools/samebytes.sh` | Assembles each module with the Makefile's flags since 10.31, and the guards and selectors; stops when a module doesn't assemble |
| `README.md`, `DESIGN.md` | 2, 4.2 |

Template alignment (the ProDOS implementation as the model, so that
maintainers find the DOS 3.3 code where they find stock's) and the
naming principle (section 2). Splitting the modules also took cc65's
ProDOS directory modules out of the core, so a program compiled with
cc65's `dirent.h` reached them in `apple2.lib`, which `cl65` appends:
shown with a test program before the guards, which linked. With them,
it fails to link. `dir_entry_count`, a cc65 extension in `apple2.h`,
reads cc65's ProDOS `DIR`, so on a2lib's it returned a wrong count; it
had no guard.

`tools/samebytes.sh` had stayed with the layout before 10.31: it
assembled the timer and reflow modules from `libsrc/dos33`, where they
no longer were, and kept going when ca65 failed, because `set -e` is off
in a subshell whose status is tested. Both trees failing alike, it could
report IDENTICAL without comparing them; it wasn't used for 10.31 or
10.32.

Verified: `tools/samebytes.sh` against 10.32 differs only in the
directory modules and guards (new and removed), `stat.s`'s symbol names
(its bytes are identical), `filetest`'s generated C (the four names) and
the `filetest` program, 4 bytes larger: the four modules are 500 bytes,
`dir.s` was 496, as `readdir`'s exits through `return0` no longer reach
with a short branch. `make emutest` passes, all 23 runs (`nettest`
included); `make linktest`, 87 checks; `make simtest`.

### 10.34 Module headers as cc65's; exec()'s stub in RODATA

| File | Change |
|---|---|
| `libsrc/dos33/*.s` (21 modules), `libsrc/timer`, `libsrc/reflow`, `libsrc/vt`, `libsrc/win`, `libsrc/s70`, `libsrc/s80`, `libsrc/ip65` (40) | Headers in cc65's form: author lines, then the prototype or a title, then the description |
| `libsrc/dos33/exec.s` | The stub's source in RODATA |

Template alignment (10.33). cc65's modules open with their authors and
the date each was written; a2lib's opened with a generic title ("DOS 3.3
file I/O for the cc65 apple2 target") or none. Now:

- a2lib's own modules: `Scott Babcock` and the date the file was added
  (git), the title kept where it said what the module is (`fm.s`,
  `rwts.s`, `irq.s`, `timer.s`);
- modified copies of stock modules (`write.s`, `crt0.s`, `mainargs.s`,
  `oserror.s`, `oserrlist.s`, the display libraries' conio modules, the
  timer's `cgetc.s` and `kbhit.s`, the reflow `cout.s`): the stock
  module's author lines, as cc65 has them, then a2lib's. The s80, window
  and Soft-70 modules had named their stock author only in their text.

`libsrc/s70/font.s` is generated by `tools/s70font.py` and keeps the
header it writes; the guards and selectors had the form already.

exec()'s stub was in DATA, but nothing writes it where it is: exec()
copies it to `target` and builds the command there (`len_t`, `cmd_t`).
Stock exec.s keeps its loader in RODATA. The strings exec() patches
(`slotdigit`, `drivedigit`) stay in DATA.

Verified: `tools/samebytes.sh` against 10.33 differs only in `exec.s`
and the three programs that link it (`exectest`, `exectestvt`,
`execatest`): the other modules are byte-identical. In `exec.o` 115
bytes move from DATA to RODATA (DATA 128 to 13, RODATA 0 to 115), and
the programs keep their sizes. `make emutest` passes, all 23 runs
(`nettest` included).

### 10.35 Size items S1-S4, S6 and S7 of the review

| File | Change |
|---|---|
| `libsrc/dos33/exec.s` | S1: the command's length and text are addressed past the copied code, at the same page-3 targets, not reserved in the stub's source |
| `libsrc/dos33/rwfile.s` | S2: five long branches that always branch (`jcc`, `jeq`, `jne`, 5 bytes) are `jmp` (3) |
| `libsrc/dos33/opendir.s` | S3: no store and reload of the name in `ptr1` before `fm_location`, which stores AX in `ptr1` itself |
| `libsrc/dos33/stat.s` | S4: no `ldy fd / tya` after `sta fd`, with `fd` in A |
| `libsrc/dos33/readdir.s` | S6: `ptr3` points at `d_name - ENT_NAME`, so one `Y` indexes the entry's name and `d_name`; `readdir` already used `ptr3`, through RWTS |
| `libsrc/vt/vt.s`, `vt.inc`, `libsrc/s80/s80.s`, `test/sim/winshim.s` | S7: the output hook's save, install and restore once, in `vt.s`, for both backends (3.5); `s80.s` drops its copies and variables; the sim stubs |

S5 was done in 10.33; S8 (the VideoTerm `cgetc` joining the stock wait
loop) was left, as it departs from the stock module's structure.

Measured as RAM (image and BSS, from the link maps), against 10.34:

| Programs | Bytes | Why |
|---|---|---|
| `exectest`, `execatest` | -55 | S1 (-45), S2 (-10) |
| `exectestvt` | -40 | S1, S2; S7 (+15) |
| `filetest` | -23 | S2, S3 (-8), S4 (-4), S6 (-1) |
| `wptest` | -10 | S2 |
| `wintest`, `reflowwin`, `cswwtest` | -52 | S7 (-93 in the file: the ONCE code it removes lies under BSS) |
| `s70test`, `reflows70`, `cswstest` | -93 | S7 |
| `vttest`, `cswtest` | +15 | S7: the calls, and `hooked`, the routine installed, compared in memory instead of as an immediate |
| `reflowvt` | +6 | S7 |

S7 was proposed at about 45 bytes saved, nothing in programs without
`s80.s`; measured, those pay 15, which was accepted for the 52 and 93
saved with it. S6 saves about 23 cycles a character, 30 characters an
entry: the copy was 43 cycles a character, and is 20.

Verified: `tools/samebytes.sh` against 10.34 differs only in those
modules, the sim stub's symbols (its bytes are unchanged) and the
programs that link them. `make simtest` passes; `make linktest`, 87
checks; `make emutest`, all 23 runs (`nettest` included).

`s70sim` measured Soft-70 0.5% slower (`cputc` 1,018 cycles a
character, from 1,013; the 70-column scroll 109,304 from 108,437; the
pan 915,457 from 910,556), though no Soft-70 code changed. S7 shrank
`s80.s`, which links before `s70.s`, so `s70.s` moved down 103 bytes.
Three backward branches now cross a page boundary: the per-scanline loop
of one-byte cells (`bne one`, up to 7 cycles a cell), a loop of the
scroll and the redraw's copy; two others no longer do. Where they land
depends on everything linked before them, so every program differs, and
moving code to restore the sim's old layout would only hide it.
Aligning the loops, or the font (3.8), needs a linker configuration that
allows it: a module's `.align` in cc65's `apple2.cfg` makes ld65 warn
that the program might not work (tried on the font). Accepted, and
documented in 3.8: Soft-70's timing varies by up to about 1% with the
program's layout.

### 10.36 The 40-column window removed

| File | Change |
|---|---|
| `libsrc/win/`, `libsrc/select/c40win.s`, `include/c40win.h` | Removed, with `lib/a2lib-c40win.lib` and its selector |
| `libsrc/s80/s80.s`, `s80.inc`, `libsrc/s70/display.inc` | The buffer is always in LOWBSS: `S80_BUFSEG` and the code for a buffer in BSS removed (the remaining code is byte-identical) |
| `libsrc/s80/*.s`, `libsrc/timer/timer.s`, `libsrc/reflow/reflow.s`, `include/a2timer.h`, `include/a2reflow.h` | Comments: Soft-70 the only 80 x 24 backend. `a2timer.h` also said every display library includes the timer; only Soft-70's does (`a2lib-vt.lib` has the tick hook and `kbhit`) |
| `test/vttest.c`, `cswtest.c`, `reflowtest.c` | The `C40WIN` builds removed (`wintest`, `cswwtest`, `reflowwin`) |
| `test/sim/gaugesim.c`, `bssfill.s`, `sim0c00.cfg` | Removed; the gauge's timing checks moved to `s70sim.c`: still shown at 0.77 s, gone after a second, restarted by a second pan, no gauge after a follow that doesn't move |
| `test/sim/winshim.s` | Renamed `vtshim.s`: the stubs are `vt.s`'s |
| `test/emutest.sh`, `test/linktest.sh`, `test/selcheck.py`, `tools/samebytes.sh`, `Makefile` | The window's runs, checks and build removed; `twodisplays` links the VideoTerm and Soft-70 libraries |
| `README.md`, `DESIGN.md` | 2, 3.1, 3.2, 3.5, 3.6 (kept, marked removed), 3.8, 3.9, 6.3 |

The window showed half of the 80 columns, panning in 20-column steps;
Soft-70 shows 70 of them. The window's one advantage was memory: it
leaves programs at `$0803`, where Soft-70's start at `$4000`, above the
hi-res page. That serves only a large program needing 80 columns
without a VideoTerm, which wasn't judged worth the backend. The model
(`libsrc/s80`) keeps its display interface (`display.inc`, the eight
`disp_` routines), with Soft-70 its only display.

`s70sim`'s timing, measured after 10.35, depended on the test as well as
the layout: the new gauge checks ended in `s70_follow`, and `cputc`
measured 1,038 cycles a character with the cursor followed, against
1,014 when not. The test now restores the earlier state (not following,
at column 10) before timing. With that, the layout's effect was
measured by linking `s70sim` with 0-252 bytes of padding ahead of the
library, in steps of 4: the ranges are in 3.8, and the scroll varies
more than the 1% stated in 10.35 (up to 3%).

Verified: `tools/samebytes.sh` against 10.35 differs, beyond the removed
files, only in the test programs whose sources changed (`vttest`,
`s70test`, `reflowtest`, `reflowvt`, `s70sim`); no library module.
`make simtest` passes, with the seven gauge checks; `make linktest`, 73
checks (the window's 14 removed); `make emutest`, all 19 runs (`nettest`
included).

### 10.37 Convention items N1-N5, N7, N8 and N10 of the review

| File | Change |
|---|---|
| `libsrc/timer/gettime.s`, `libsrc/s70/cgetc.s`, `libsrc/s80/gotoy.s`, `libsrc/s80/cpeekc.s`, `libsrc/vt/cpeekc.s`, `libsrc/vt/cgetc.s` | N1: named labels for jumps past another label (`:++`, `:--`), as the conventions ask (10.20); the stock wait loops of `vt/cgetc.s` and `timer/cgetc.s` keep theirs |
| `libsrc/dos33/fmbuf.s` | N2: `.assert .sizeof(FD) = 4` over the four `inx` stepping through `fdtab`, as `open.s` has |
| `libsrc/dos33/dir.inc`, `opendir.s` | N3: `DOS_SECTORS`, `DOS_TSPAIRS`, `DOS_TRACKS` in place of 16, 122 and 35 in the VTOC checks |
| `libsrc/dos33/stat.s` | N4: no `filedes.inc`, which it didn't use, and no empty RODATA |
| `libsrc/dos33/exec.s` | N5: the header's failure paragraph rewrapped (it broke mid-sentence and ran to 109 columns) |
| `include/a2timer.h`, `libsrc/timer/timer.s` | N7: `a2_timer_start` marked `__fastcall__`, which takes its last argument in A; cc65's default already, so for consistency with the other prototypes |
| `libsrc/vt/*.s` (8 modules) | N8: "(DESIGN.md 3.4)." joined to the sentence it ends, left alone on a line by an earlier reflow |
| `libsrc/dos33/initcwd.s` | N10: `.code`, as every other module names its segment |

N6 (an equate alone in the window's ONCE) left with the window (10.36).
N9: 10.20 says `machine.inc` defines `BASIC_BUF` "only if not already",
as stock `mainargs.s` defined it too. 10.22 dropped the condition with
the ProDOS paths (a2lib's `mainargs.s` takes it from `machine.inc`), so
since then it's defined unconditionally; 10.20 stays as written.

Verified: `tools/samebytes.sh` reports the tree IDENTICAL to 10.36, every
module and program, the C tests compiled with the changed `a2timer.h`
included.

### 10.38 The symbol index (`make tags`)

| File | Change |
|---|---|
| `tools/ca65.ctags` | New: a Universal Ctags definition of ca65 source (labels, `=` and `:=` constants, `.define` names, macros, structs and their fields, `.proc` and `.scope` names) |
| `Makefile` | `tags`: a2lib's sources (`libsrc`, `include`, `test`) and cc65's (`libsrc/apple2`, `common`, `runtime`, `asminc`, `include` of `CC65_SRC`, by default the checkout of the `cl65` in use) indexed with it; rebuilt when an a2lib source changes; part of `make` when Universal Ctags is found (`CTAGS`, a Homebrew one looked for too) |
| `.gitignore` | `/tags` |
| `README.md` | Building: the index |

For go-to-definition in an editor while working through the sources.
`--options=NONE` keeps a local `.ctags.d` from defining ca65 twice.
Verified on Debian with Universal Ctags 5.9: `make` builds `tags` (it
finds `fm_getfcb`, `DOS_BUFS`, `fdtab`, `popax`), a second `make` does
nothing, touching a source rebuilds it, and with `CTAGS=` `make` skips it
while `make tags` says why and fails. `tools/samebytes.sh`: identical, as
nothing that's built changed.

### 10.39 Names for shared storage: the file layer

| File | Change |
|---|---|
| `libsrc/dos33/fm.inc` | `fm_parmlist` and `ctlblock`, text macros for `ptr3` and `ptr4` |
| `libsrc/dos33/dir.inc` | `dirptr` for `ptr1`; `read_dir_sector_ptr1` and `rewinddir_ptr1` renamed `read_dir_sector` and `rewind_dir`, as their input now has a name |
| `libsrc/dos33/fm.s`, `fmbuf.s`, `fmname.s`, `open.s`, `seekend.s`, `sysrename.s`, `lseek.s`, `rwts.s`, `rwfile.s`, `rwcommon.s`, `exec.s`, `opendir.s`, `rewinddir.s`, `readdir.s`, `stat.s` | The cells named for what they hold (code and comments) |

The vendored `write.s` and `mainargs.s` keep stock's names.

Verified: `tools/samebytes.sh` against `f85d189` reports only the
symbol tables of `opendir.s`, `readdir.s` and `rewinddir.s`, for the two
renamed routines; with those two names put back, it reports the tree
IDENTICAL, every module and program.

### 10.40 Routine headers: the file layer

| File | Change |
|---|---|
| `libsrc/dos33/fm.s`, `fmbuf.s`, `fmname.s`, `rwts.s` | Headers for the File Manager, buffer, name and RWTS routines |
| `libsrc/dos33/open.s`, `rwfile.s`, `rwcommon.s`, `write.s`, `lseek.s`, `seekend.s` | Headers for open(), the read and write paths, lseek() and O_APPEND |
| `libsrc/dos33/stat.s`, `opendir.s`, `readdir.s`, `rewinddir.s`, `closedir.s` | Headers for stat() and the directory routines |
| `libsrc/dos33/sysremove.s`, `sysrename.s`, `syschdir.s`, `initcwd.s`, `exec.s`, `oserror.s`, `oserrlist.s` | Headers for the remaining entry points, exec()'s stub and the error tables |

Each module's storage is commented with its type. Comments only.

Verified: `tools/samebytes.sh` against `674ba13` reports the tree
IDENTICAL, every module and program.

### 10.41 remove() and rename(): no X for ___mappederrno

| File | Change |
|---|---|
| `libsrc/dos33/sysremove.s`, `sysrename.s` | The `ldx #$00` before `rts` removed: the only callers, cc65's `common/remove.s` and `common/rename.s`, end in `___mappederrno`, which sets X from A. Stock apple2's modules don't set X either. 2 bytes each |
| `libsrc/dos33/syschdir.s` | Header: the same note on X |

Verified: `tools/samebytes.sh` against `c664afa` reports only
`sysremove.s`, `sysrename.s` and the programs that link them
(`filetest`, `wptest`); `make emutest` passes.

### 10.42 Names for shared storage: the runtime

| File | Change |
|---|---|
| `libsrc/timer/gettime.s`, `settime.s` | `tp` for `ptr1`, the `struct timespec*` argument |

The other runtime modules use no cc65 zero-page cell except as stock
does: `timer.s` saves and restores the whole block from `sreg` around
callbacks, and `sreg` carries `a2_millis()`'s and `a2_clock_age()`'s
high word. The vendored `crt0.s`, `mainargs.s`, `cgetc.s` and `kbhit.s`
keep stock's names.

Verified: `tools/samebytes.sh` against `92a7d3d` reports the tree
IDENTICAL, every module and program.

### 10.43 Routine headers: the runtime

| File | Change |
|---|---|
| `libsrc/dos33/crt0.s`, `irq.s`, `mainargs.s` | Headers for start-up, the vectors, the interrupt handlers and the argument constructor |
| `libsrc/timer/timer.s`, `tick.s`, `cgetc.s`, `kbhit.s`, `gettime.s`, `settime.s` | Headers for the cooperative timer, its hook, its wait loops and the software clock |
| `libsrc/ip65/a2timer.s` | Headers for IP65's timer interface |

Each module's storage is commented with its type. Comments only.

Verified: `tools/samebytes.sh` against `e60ca38` reports the tree
IDENTICAL, every module and program.

### 10.44 Names for shared storage: the display libraries

| File | Change |
|---|---|
| `libsrc/s70/s70.s` | `source` and `dest` for `ptr1` and `ptr2`, s70_font's font set and its place in the font table |

No other display module uses a cc65 zero-page cell except as stock
does: the vendored `vt/cgetc.s` and `vt/cputc.s` keep the character
under the caret in `tmp3`, cc65's convention between the two, under
stock's name. Soft-80 and Soft-70 use the monitor's `BASL` and
`BAS2L` as their pointers, under the monitor's names.

Verified: `tools/samebytes.sh` against `042175d` reports the tree
IDENTICAL, every module and program.

### 10.45 Routine headers: the display libraries

| File | Change |
|---|---|
| `libsrc/vt/*.s` | Headers for VideoTerm's detection, output hooks, firmware calls and conio modules |
| `libsrc/s80/*.s` | Headers for the 80 x 24 model, its C interface, the position gauge and its conio modules |
| `libsrc/s70/s70.s`, `cgetc.s`, `rdkey.s` | Headers for Soft-70's drawing, scrolling, gauge, cursor and font routines, and its input |
| `libsrc/reflow/*.s` | Headers for reflow_on, reflow_off, the filter, COUT and the stock screen's width |
| `libsrc/timer/timer.s` | A field that overflowed its column, rewrapped |

The file headers of `vt.s` and `s80.s` no longer list their routines,
which have headers of their own. `s70/font.s` is generated by
`tools/s70font.py` and holds only the font, so its file header is all it
has. Each module's storage is commented with its type. Comments only.

Verified: `tools/samebytes.sh` against `810c917` reports the tree
IDENTICAL, every module and program.

### 10.46 Addresses by name

| File | Change |
|---|---|
| `libsrc/dos33/machine.inc` | New: `MON_RDKEY` ($FD0C), and Applesoft's `HIGHDS`, `HIGHTR` and `LOWTR` ($94, $96, $9B), BLTU2's pointers |
| `libsrc/dos33/crt0.s`, `irq.s` | The language card switches by name (`ROMIN`, `LCBANK2`, `LC_ROM_RO`, `LC_BANK2_RO`), and BLTU2's pointers |
| `libsrc/vt/cout.s`, `rdkey.s`, `libsrc/s70/rdkey.s`, `libsrc/reflow/cout.s` | The switches, `MON_COUT` and `MON_RDKEY` by name; they include `machine.inc` |
| `Makefile` | The VideoTerm, Soft-70 and sim objects depend on `libsrc/dos33/*.inc`, which they include |

Verified: `tools/samebytes.sh` against `1c70002` reports the tree
IDENTICAL, every module and program; `make simtest` passes.

### 10.47 Comments realigned after 10.46

| File | Change |
|---|---|
| `libsrc/dos33/crt0.s`, `irq.s`, `libsrc/vt/cout.s`, `rdkey.s`, `libsrc/s70/rdkey.s`, `libsrc/reflow/cout.s` | The comments after the renamed operands back at column 33, where 10.46's longer names had pushed them |

Verified: `tools/samebytes.sh` against `12d4d65` reports the tree
IDENTICAL, every module and program.

### 10.48 Prerequisites in `Prepare:`, throughout

| File | Change |
|---|---|
| `libsrc/dos33/write.s`, `lseek.s`, `rwcommon.s`, `readdir.s`, `rewinddir.s`, `closedir.s`, `libsrc/timer/timer.s` | `Prepare:` for the public functions that take what another returns: `open()`, `opendir()`, `a2_timer_start()` |
| `libsrc/dos33/fm.s`, `fmbuf.s`, `open.s`, `opendir.s`, `rewinddir.s`, `seekend.s`, `sysrename.s`, `rwcommon.s`, `libsrc/vt/vt.s`, `libsrc/ip65/a2timer.s` | `Prepare:` for the internal routines that lacked it; prerequisites that were written into Input lines moved there; `fm_call`'s and `truncate`'s naming routines only |
| `DESIGN.md` | The header convention says what `Prepare:` names |

Comments only.

Verified: `tools/samebytes.sh` against `961733c` reports the tree
IDENTICAL, every module and program.

### 10.49 Headers: summaries, signatures and overrides

| File | Change |
|---|---|
| Every module and include file in `libsrc/`, but the unmodified `filedes.inc` and `mli.inc` | File headers rewritten as summaries of what each file holds, keeping the authors; no C signatures, no other source files named; the design pointed to as "For details, see section N of DESIGN." |
| Every routine header | No name line; `Signature:` and `Overrides:` fields in place of signatures and "which dirent.h names ..." in the description; no `void` in empty argument lists; no `Input: none` or `Output: none`; references to other source files and to DESIGN.md sections in comments reworded the same way |
| `tools/s70font.py`, `libsrc/s70/font.s` | The generated header in the same form |
| `include/*.h` | Design pointers in the same form |
| `DESIGN.md` | The header conventions |

Comments only.

Verified: `tools/samebytes.sh` against `5e31003` reports the tree
IDENTICAL, every module and program.

### 10.50 Register pairs and meanings in headers

| File | Change |
|---|---|
| 43 modules in `libsrc/` | Register pairs as `X:A`, `A:X`, `A:Y` and `sreg:X:A`, one line each, in place of `AX`, `sreg:AX`, `AX, sreg` and pairs split over two lines; meanings in words, without the C parameter's name; the comments on the two `LOCATE` calls the same way |
| `DESIGN.md` | The key to the notation, in the header convention |

Comments only.

Verified: `tools/samebytes.sh` against `cab6e0a` reports the tree
IDENTICAL, every module and program.

### 10.51 The language card switches by a2lib's names

| File | Change |
|---|---|
| `libsrc/dos33/machine.inc` | `LC_ROM_WRAM` ($C081) and `LC_BANK2_RW` ($C083), beside `LC_BANK2_RO` and `LC_ROM_RO`, in address order |
| `libsrc/dos33/crt0.s`, `irq.s` | `LC_ROM_WRAM` and `LC_BANK2_RW` in place of cc65's `ROMIN` and `LCBANK2` |
| `DESIGN.md` | The convention: cc65's names only where they say what the location does |

Verified: `tools/samebytes.sh` against `002c52e` reports the tree
IDENTICAL, every module and program.

### 10.52 The catalog's layout as structs

| File | Change |
|---|---|
| `libsrc/dos33/dir.inc` | The VTOC, a catalog sector and a catalog entry as `.struct`s, in place of offset constants; the entries per catalog sector and the T/S pairs per T/S list sector computed from the layouts, with assertions of DOS 3.3's values (35-byte entries, 7 per sector, 122 pairs); the VTOC's offsets no longer duplicate the values they're checked against |
| `libsrc/dos33/opendir.s`, `readdir.s` | The struct fields in place of the constants |

Verified: `tools/samebytes.sh` against `572f97d` reports the tree
IDENTICAL, every module and program.

## 11. Sources

- cc65, commit `eebf54a`: `libsrc/apple2/` (`filedes.*`, `open.s`,
  `read.s`, `write.s`, `rwcommon.s`, `lseek.s`, `mli.s`, `oserror.s`,
  `opendir.s`, `readdir.s`, `closedir.s`, `rewinddir.s`, `dir.inc`,
  `filename.s`, `diocommon.s`, `irq.s`, `crt0.s`, `cout.s`,
  `detect80cols.s`, `lseek.s`, `stat.s`, `sysremove.s`, `sysrename.s`),
  `libsrc/common/` (`fgets.s`, `fgetc.s`, `vfscanf.s`, `remove.s`),
  `include/dirent.h`, `include/sys/stat.h`, `asminc/stat.inc`,
  `cfg/apple2.cfg`, `doc/apple2.sgml`
- IP65: `drivers/uthernet2.s`, `drivers/w5100.s`
- *Beneath Apple DOS*, chapters 4, 5, 6, 8 (transcribed text,
  github.com/knghtbrd/beneath-apple-dos)
- ReplicApple2Plus: `HARDWARE-REFERENCE.md` §3,
  `VideoTermFirmwareIntegrationTest`
- Videx VideoTerm firmware 2.4 disassembly and ROM image `BBE3BB28`
  (6502bench SourceGen; github.com/btb/80ColumnCard)
- Videx VideoTerm Installation and Operation Manual, 3rd ed. (1982)
