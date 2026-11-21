;
; Scott Babcock, 2026-11-14
;
; a2_viewport: the visible width of the text screen, in A (DESIGN.md 3.7)
;
; Soft-70 (a2lib-soft70.lib): 80 on the VideoTerm; otherwise S80_VIEW
; (display.inc), the columns of the 80 x 24 screen shown at a time, 70.
;

        .export         a2_viewport

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

a2_viewport:
        lda     #VT_COLS
        bit     vt_active
        bmi     :+
        lda     #S80_VIEW
:       rts
