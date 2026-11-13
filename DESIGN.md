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

**Link guard:** the header maps `opendir`, `readdir`, `closedir` and
`rewinddir` to `_dos33_*` symbols that exist only in `apple2-dos33.lib`.

- Header without the library: the link fails (verified: ld65 reports
  `__dos33_opendir` as unresolved).
- Library without the header: the program uses cc65's stock directory
  modules, which are still in the library under their stock names. They
  fail visibly with `EINVAL`, because this layer's `open` rejects the
  ProDOS pathnames they pass.

Either way, the DOS 3.3 `struct dirent` is never mixed with the ProDOS
implementation.

**The add-on library is a complete library (decision, from the first run
of increment 2):** `lib/apple2-dos33.lib` is a copy of the installed
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

### 3.5 VideoTerm implementation (increment 5)

**Packaging.** `lib/apple2-dos33-vt.lib` is `apple2-dos33.lib` with
VideoTerm-aware versions of the stock conio modules (`libsrc/vt/`). It is
the link-time choice of section 3.1: programs that don't want the backend
link `apple2-dos33.lib` and pay nothing. Each replaced module is a
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

### 3.6 40-column window implementation (increment 6)

**Packaging.** `lib/apple2-dos33-vtwin.lib` holds the VideoTerm backend
with the 40-column window (`c40win`) as its fallback, in place of the
stock 40-column screen (section 3.1: a binary contains the VideoTerm
backend plus one fallback). It is `apple2-dos33.lib` plus `vt.s`, shared
unchanged with `apple2-dos33-vt.lib`, plus the window's conio modules
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

The DOS 3.3 build has its own layout (`include/dirent.h`; section 5.9
gives the fields). This is the one public-header change (see section 2).
It's the change most likely to need discussion upstream; it goes to the
cc65 maintainers together with working code (section 9).

**Revised in increment 3:** the first draft had `d_type` hold the DOS
file type. Following the guiding principle, `d_type` instead holds the
ProDOS-equivalent type, as `stat`'s `st_type` does, so code that tests
file types works under both DOSes; the DOS type is in a separate
`d_dostype` field.

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

### 5.5a remove and rename

- `remove` uses the File Manager's DELETE. A locked file fails with
  `EACCES`, as under ProDOS.
- `rename` uses RENAME. The old name may carry suffixes; **the new name
  may not**, since the file stays where it is. A new name with a suffix
  fails with `EINVAL`, so the location is never ambiguous.
- DOS's RENAME doesn't check whether the new name is already in use and
  would leave two files with the same name. **As under ProDOS, an
  existing new name fails with `EEXIST`**: `rename` first tries to OPEN
  the new name without allocating it.
- Both need the File Manager's work area and buffers even without an
  open file, so they allocate a temporary control block (557 bytes).
  If that fails, they return ProDOS code `$25`, which maps to `ENOMEM`;
  the ProDOS table has no closer code, because stock cc65 allocates
  nothing for these calls.
- **Known difference (open):** ProDOS refuses to delete or rename an open
  file (`$50`, `EINVAL`). DOS 3.3 doesn't check, and this layer doesn't
  yet record names in the control block to detect it. Deleting or
  renaming a file that is open is therefore not detected.

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
| `st_access` | `$01` (read only) if locked, else `$C3` (cc65's default for new ProDOS files) |
| `st_type` | ProDOS equivalent: T `$04`, B `$06`, A `$FC`, I `$FA`, R `$FE`; others `$00` |
| `st_auxtype` | B: the load address; others 0 |
| `st_blocks` | 512-byte blocks, `(sectors + 1) / 2`, from the file's catalog entry: the same value `readdir` gives in `d_blocks` (5.9) |
| others | 0. DOS 3.3 keeps no dates. |

Filling `st_blocks` means `stat` reads the catalog (through the same
code as `readdir`), so `stat` pulls in the directory module: about 650
bytes more in programs that use `stat` (increment 3).

### 5.9 Directories

DOS 3.3 has no subdirectories, so a "directory" is a disk's catalog.
`opendir` takes a **location instead of a path**: `""` or `"."` for the
last-used slot and drive, optionally followed by suffixes as at the DOS
prompt (`",D2"`, `".,S6,D2"`, `",V254"`). An explicit S or D becomes
DOS's default, as for file names (5.5). Anything else fails with `EINVAL`.

**Reading the catalog.** The File Manager's CATALOG call only prints, so
the catalog is read directly through RWTS (*Beneath Apple DOS* ch. 4, 6):

- `opendir` reads the VTOC (track 17, sector 0) and checks that it is a
  DOS 3.3 VTOC: 16 sectors per track, 122 track/sector pairs per list
  sector, and a first catalog sector on the disk. Otherwise it fails
  with ProDOS code `$52`, which maps to `ENODEV`, so a disk that isn't
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
  codes are translated to ProDOS codes (`rwts_maperr`): write protect →
  `EACCES`, volume mismatch → `ENOENT`, drive or read errors → `EIO`.

**`struct dirent`** (`include/dirent.h`):

| Field | Value |
|---|---|
| `d_name[31]` | Up to 30 characters; bit 7 cleared, trailing blanks removed |
| `d_ino` | T/S list location, track × 256 + sector (unique on the disk) |
| `d_blocks` | 512-byte blocks, `(d_sectors + 1) / 2`: the unit of POSIX and ProDOS |
| `d_type` | ProDOS-equivalent type, as `st_type`: T `$04`, B `$06`, A `$FC`, I `$FA`, R `$FE`; others `$00` |
| `d_access` | `$01` (read only) if locked, else `$C3`, as `st_access` |
| `d_sectors` | Length in sectors, as CATALOG shows (the DOS idiom) |
| `d_dostype` | DOS type in catalog coding, without the lock bit |

**Fields left out (decision).** cc65's ProDOS `struct dirent` also has
`d_size`, `d_ctime`, `d_mtime` and `d_auxtype`. The catalog has no byte
size, no dates and no load address; a byte size would take opening each
file (and, for T files, scanning it). Rather than fill them with zeros,
the DOS 3.3 struct leaves them out, so **code that relies on them fails
to compile** instead of silently reading wrong values. `stat` gives a
file's exact size and load address.

---

## 6. DOS 3.3 interrupts

**(verified)** cc65's `initirq` simply asks the ProDOS MLI to allocate an
interrupt and prints "FAILED TO ALLOC INTERRUPT" otherwise. `crt0.s`
already installs an IRQ forwarding routine in the Language Card vectors
for non-ProDOS programs. **Decision:** a DOS 3.3 `initirq`/`doneirq` that
hooks the monitor's IRQ vector at `$3FE`, chaining the previous handler,
selected at link time like the other modules.

### 6.1 Design (increment 4)

`libsrc/dos33/irq.s` replaces stock `irq.s`. Its ProDOS path is stock
cc65's, unchanged, so a DOS 3.3 build run under ProDOS still allocates
an interrupt through the MLI.

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
itself: the 40-column window's position indicator (a gauge hidden after
a delay), IP65's timer, and a software clock for `time()` and
`clock_gettime()` under DOS 3.3, which programs can set from an Internet
time server (IP65 includes an SNTP client, `sntp_get_time`).
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
the gauge uses the timer, programs linked with `apple2-dos33-vtwin.lib`
include `timer.s` (`wintest` grew by 1,374 bytes, gauge checks included).

**Testing in sim65 (`make simtest`).** cc65's 6502 simulator runs the
real modules, built for its `sim6502` target, with stubs for the few
Apple II-only imports: `test/sim/timersim.c` checks the Bresenham
arithmetic against an exact model, ms-to-tick rounding (100 ms = 26
ticks), one-shot and periodic timers, slot limits, zero-page
preservation and the clock, and measures `a2_tick` with sim65's cycle
counter; `test/sim/gaugesim.c` links the real `win.s` (at `$0C00`, so
the text screen is free) and checks what the gauge leaves on screen. It
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

Programs link with
`cl65 -t apple2 -o prog prog.c lib/apple2-dos33.lib`; the library is a
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

The Makefile builds `lib/apple2-dos33-vt.lib` alongside
`apple2-dos33.lib`. **Verified by building:** the VideoTerm modules
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

The Makefile builds `lib/apple2-dos33-vtwin.lib`.

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

### 10.9 Next increments

- Display backends: the reflow filter (decided in 3.2: activated at run
  time, linked on demand, breaking at the viewport width) and Soft-70
  (section 3)
- Emulator test fixture (section 8)
- Detect deleting or renaming an open file, as ProDOS does (5.5a)

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
