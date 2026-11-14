;
; a2_viewport: the visible width of the text screen, in A (DESIGN.md 3.7)
;
; VideoTerm library: 80 on the card, otherwise the stock 40-column screen.
;

        .export         a2_viewport

        .include        "apple2.inc"
        .include        "vt.inc"

a2_viewport:
        lda     #VT_COLS
        bit     vt_active
        bmi     :+
        lda     WNDWDTH
:       rts
