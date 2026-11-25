;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; clrscr() for the Soft-70 library: the VideoTerm's screen, or the 80 x 24
; model's. For details, see section 3.8 of DESIGN.
;

        .export         _clrscr

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; Clear the screen and home the cursor: on the VideoTerm, with the firmware's
; $0C; otherwise s80_clear.
;
; Signature:    void clrscr ()
; Overrides:    cc65's clrscr()
; Changes:      A and flags; the screen and the cursor. In the model: X, Y,
;               BAS2L and the buffer, and the display's redraw.

_clrscr:
        bit     vt_active
        bmi     :+
        jmp     s80_clear
:       lda     #$0C
        jmp     vt_write
