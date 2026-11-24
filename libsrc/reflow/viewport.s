;
; Scott Babcock, 2026-11-13
;
; a2_viewport: the visible width of the text screen, in A (DESIGN.md 3.7)
;
; Used by reflow.s for its default line width. Each library has its own
; version: here, the stock 40-column screen (the monitor's window width).
;

        .export         a2_viewport

        .include        "apple2.inc"

;-----------------------------------------------------------------------------
; a2_viewport: The visible width of the stock 40-column screen, for reflow_on:
; the monitor's window width.
;
; Input:        none
; Output:       A             byte      WNDWDTH
; Changes:      Flags. X and Y are unchanged.

a2_viewport:
        lda     WNDWDTH
        rts
