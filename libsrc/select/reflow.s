;
; Scott Babcock, 2026-11-20
;
; The reflow library's selector, linked as lib/a2lib-reflow.o, ahead of
; a2lib-reflow.lib and a2lib-dos33.lib. It pulls in the library's COUT, which
; the filter is switched into, in place of cc65's, which write() and read()
; reach; all of stdio does, so they can't be copied into the library. A
; display library's selector, listed first, pulls in that library's COUT
; instead. For details, see sections 2 and 3.7 of DESIGN.
;

        .forceimport    COUT
