;
; Scott Babcock, 2026-11-14
;
; The visible width of the text screen, for reflow_on()'s default: 80 on the
; VideoTerm, else S80_VIEW, the 70 columns Soft-70 shows. For details, see
; section 3.7 of DESIGN.
;

        .export         a2_viewport

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The visible width of the text screen, for reflow_on: 80 on
; the VideoTerm, else S80_VIEW.
;
; Output:       A             byte      the width in columns
; Changes:      Flags. X and Y are unchanged.

a2_viewport:
        lda     #VT_COLS
        bit     vt_active
        bmi     :+
        lda     #S80_VIEW
:       rts
