;
; Scott Babcock, 2026-11-20
;
; Selector for a2lib-timer.lib, the cooperative timer and software clock
; (DESIGN.md 2, 6.3): linked as lib/a2lib-timer.o, ahead of a2lib-timer.lib
; and a2lib-dos33.lib.
;
; It pulls in nothing. The stock modules that call the timer library's
; cgetc, kbhit and clock_gettime (cgets, cscanf, time, and cc65's
; debugger) are copied into it (tools/stockcopy.py), so ld65 resolves their
; calls there, and no module after the library calls into it otherwise.
; The object exists so that every add-on is linked the same way, with its
; selector; leaving it out changes nothing. test/linktest.sh checks that
; it needn't pull anything in (test/selcheck.py).
;
