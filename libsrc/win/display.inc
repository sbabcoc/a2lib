;
; 40-column window: parameters of the shared 80 x 24 model (s80.inc)
;
; The window shows 40 of the 80 columns on the 40-column text screen,
; panning in steps of 20 (DESIGN.md 3.6).
;

S80_VIEW        = 40
S80_STEP        = 20
.define         S80_API         "_c40_"
.define         S80_BUFSEG      "BSS"

; Screen codes are the text screen's: INVFLG masks them as the monitor's
; COUT does, and cpeekc inverts bit 7 as cc65's does.

.macro  S80_ATTR
        and     INVFLG
.endmacro

.macro  S80_PEEK
        eor     #$80
.endmacro

; Encoding of the buffer for the text marker (DESIGN.md 3.9; the window,
; with its buffer in BSS, writes none): bytes XOR $A0 give text screen
; codes
S80_TEXTENC     = 0
