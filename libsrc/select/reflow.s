;
; Scott Babcock, 2026-11-20
;
; Selector for a2lib-reflow.lib, the reflow filter (DESIGN.md 2, 3.7):
; linked as lib/a2lib-reflow.o, ahead of a2lib-reflow.lib and
; a2lib-dos33.lib, it pulls in the library's COUT, a vector the filter is
; switched into, in place of stock cout.s, which write and read reach. A
; display library's selector, listed first, pulls in that library's COUT
; (also a vector) instead. test/linktest.sh checks that this is the only
; module it needs to pull in.
;

        .forceimport    COUT
