;
; Scott Babcock, 2026-11-20
;
; Selector for a2lib-c40win.lib, the 40-column window backend (DESIGN.md 2):
; linked as lib/a2lib-c40win.o, ahead of a2lib-c40win.lib and
; a2lib-dos33.lib.
;
; ld65 scans each library once. A stock module that calls into the backend
; resolves its calls in the library it comes from: from the core, stock
; cputs would call stock cputc. So a2lib-c40win.lib holds copies of the
; core's modules that do (tools/stockcopy.py: cputs, cprintf, cgets, cscanf
; and the like), taken, with the backend's, when ld65 scans it. That leaves
; the backend's modules that a module linked after the library may import
; and that can't be copied: the core's write and read (all of stdio reaches
; them) and reflow.s, in a2lib-reflow.lib. This object pulls those in:
;
;   COUT            write; with it, a2_coutvec and a2_rawcout, for reflow_on
;   RDKEY           read
;   _wherex         reflow_on, for the cursor's column
;   a2_viewport     reflow_on, for the visible width
;
; It also defines the symbol vt.s requires, so that the display library
; without its selector fails to link, and two display libraries fail with
; a duplicate symbol. test/linktest.sh checks this list against the
; libraries (test/selcheck.py).
;

        .forceimport    COUT, RDKEY, _wherex, a2_viewport

        .export         a2lib_display_needs_selector_object: absolute
a2lib_display_needs_selector_object := 0
