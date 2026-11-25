;
; Scott Babcock, 2026-11-20
;
; The timer library's selector, linked as lib/a2lib-timer.o, ahead of
; a2lib-timer.lib and a2lib-dos33.lib. It pulls in nothing: the cc65 modules
; that call the library's cgetc(), kbhit() and clock_gettime(), such as
; cgets(), cscanf(), time() and cc65's debugger, are copied into the library,
; so ld65 resolves their calls there. The object exists so that every add-on
; is linked the same way; leaving it out changes nothing. For details, see
; sections 2 and 6.3 of DESIGN.
;
