;
; Scott Babcock, 2026-11-13
;
; The visible width of the text screen, for reflow_on()'s default: here, the
; stock screen's window width. Each library has its own. For details, see
; section 3.7 of DESIGN.
;

        .export         a2_viewport

        .include        "apple2.inc"

;-----------------------------------------------------------------------------
; The visible width of the stock 40-column screen, for reflow_on: the
; monitor's window width.
;
; Output:       A             byte      WNDWDTH
; Changes:      Flags. X and Y are unchanged.

a2_viewport:
        lda     WNDWDTH
        rts
