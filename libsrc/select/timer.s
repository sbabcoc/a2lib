;
; Scott Babcock, 2026-11-20
;
; Selector for a2lib-timer.lib, the cooperative timer and software clock
; (DESIGN.md 2, 6.3): linked as lib/a2lib-timer.o, ahead of a2lib-timer.lib
; and a2lib-dos33.lib, it pulls in each module of a2lib-timer.lib that
; replaces one that a core module may import:
;
;   _cgetc          cgets and cscanf call it; the timer's runs timers while
;                   waiting for a key
;   _clock_gettime  time calls it; a2lib-dos33.lib has only a guard
;   _kbhit          dbg calls it
;
; ld65 scans each library once: without this, only what the program calls
; by name would come from a2lib-timer.lib, and the rest from the core.
; test/linktest.sh checks that this list is that set.
;

        .forceimport    _cgetc, _clock_gettime, _kbhit
