;
; Scott Babcock, 2026-11-20
;
; Selector for a2lib-vt.lib, the VideoTerm backend (DESIGN.md 2): linked as
; lib/a2lib-vt.o, ahead of a2lib-vt.lib and a2lib-dos33.lib, it pulls in
; each module of a2lib-vt.lib that replaces one that a module linked after
; it may import: stock conio and stdio modules, the core's read and write,
; and the add-ons listed after it. Without it, ld65, which scans each
; library once, would take only what the program calls by name from a2lib-
; vt.lib, and the rest from the core: a program calling only cputs would get
; stock cputc. test/linktest.sh checks that this list is that set.
;
;   _cgetc          cgets, cscanf; dbg
;   _cputc          cputs, cprintf, cgets, cscanf, cputhex; and with it
;                   putchar, newline, cputdirect (chline, cvline), _cputcxy
;   gotoxy          cputs, cclear, chline, cvline (and _gotoxy: cgets)
;   _wherex         cgets, reflow_on
;   _wherey         cgets
;   screensize      screensize()
;   COUT, RDKEY     write, read; with COUT, a2_coutvec and a2_rawcout for
;                   reflow_on
;   _clrscr, _kbhit dbg
;   a2_viewport     reflow_on, for the visible width
;
; _cpeekc, _gotoy and _gotox aren't listed: no other module calls them.
;

        .forceimport    _cgetc, _cputc, gotoxy, _wherex, _wherey, screensize
        .forceimport    COUT, RDKEY, _clrscr, _kbhit, a2_viewport
