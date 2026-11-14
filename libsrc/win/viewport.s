;
; a2_viewport: the visible width of the text screen, in A (DESIGN.md 3.7)
;
; Window library: 80 on the VideoTerm; otherwise 40, the columns of the
; 80 x 24 screen that the window shows at a time.
;

        .export         a2_viewport

        .include        "win.inc"
        .include        "vt.inc"

a2_viewport:
        lda     #VT_COLS
        bit     vt_active
        bmi     :+
        lda     #WIN_VIEW
:       rts
