;
; a2_viewport: the visible width of the text screen, in A (DESIGN.md 3.7)
;
; Used by reflow.s for its default line width. Each library has its own
; version: here, the stock 40-column screen (the monitor's window width).
;

        .export         a2_viewport

        .include        "apple2.inc"

a2_viewport:
        lda     WNDWDTH
        rts
