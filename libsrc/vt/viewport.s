;
; Scott Babcock, 2026-11-13
;
; The visible width of the text screen, for reflow_on()'s default: 80 on the
; card, else the stock screen's window width. For details, see section 3.7 of
; DESIGN.
;

        .export         a2_viewport

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The visible width of the text screen, for reflow_on: 80 on
; the card, else the window's width.
;
; Output:       A             byte      the width in columns
; Changes:      Flags. X and Y are unchanged.

a2_viewport:
        lda     #VT_COLS
        bit     vt_active
        bmi     :+
        lda     WNDWDTH
:       rts
