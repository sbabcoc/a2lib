;
; Scott Babcock, 2026-11-20
;
; The Soft-70 library's selector, linked as lib/a2lib-soft70.o, ahead of
; a2lib-soft70.lib and a2lib-dos33.lib.
;
; ld65 scans each library once. A stock module that calls into the display
; resolves its calls in the library it comes from: from cc65's library,
; cputs() would call cc65's cputc(). So the display library holds copies of
; cc65's modules that do, such as cputs(), cprintf(), cgets() and cscanf(),
; taken with the display's own when ld65 scans it. That leaves the display's
; modules that a module linked after the library may import, and that can't be
; copied: cc65's write() and read(), which all of stdio reaches, and the
; reflow library. This object pulls those in:
;
;   COUT            write(); with it, a2_coutvec and a2_rawcout, for
;                   reflow_on()
;   RDKEY           read()
;   _wherex         reflow_on(), for the cursor's column
;   a2_viewport     reflow_on(), for the visible width
;
; It also defines the symbol the display requires, so that the display library
; without its selector fails to link, and two display libraries together fail
; with a duplicate symbol. For details, see section 2 of DESIGN.
;

        .forceimport    COUT, RDKEY, _wherex, a2_viewport

        .export         a2lib_display_needs_selector_object: absolute
a2lib_display_needs_selector_object := 0
