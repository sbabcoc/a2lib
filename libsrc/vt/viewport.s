;
; Scott Babcock, 2026-11-13
;
; a2_viewport: the visible width of the text screen, in A (DESIGN.md 3.7)
;
; VideoTerm library: 80 on the card, otherwise the stock 40-column screen.
;

        .export         a2_viewport

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; a2_viewport: The visible width of the text screen, for reflow.s (DESIGN.md
; 3.7): 80 on the card, else the window's width.
;
; Input:        none
; Output:       A             byte      the width in columns
; Changes:      Flags. X and Y are unchanged.

a2_viewport:
        lda     #VT_COLS
        bit     vt_active
        bmi     :+
        lda     WNDWDTH
:       rts
