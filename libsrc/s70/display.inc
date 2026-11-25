;
; Soft-70's parameters for the 80 x 24 model: 70 of the 80 columns shown on
; hi-res page 1, panning between columns 0-69 and 10-79. The model's buffer is
; in LOWBSS, below the hi-res page, so that it doesn't take space from the
; program. For details, see section 3.8 of DESIGN.
;

S80_VIEW        = 70
S80_STEP        = 10
.define         S80_API         "_s70_"

; Screen codes: bit 7 set for normal video, clear for inverse; bits 0-6 the
; character, $00-$1F standing for controls shown as their letters (the
; screen codes $80-$9F of the text screen). Unlike the text screen's
; inverse codes, these keep lowercase and punctuation distinct, since the
; font has a glyph for each. Flashing (INVFLG $7F) shows as inverse.

.macro  S80_ATTR
        .local  normal
        bit     INVFLG
        bmi     normal
        and     #$7F
normal:
.endmacro

.macro  S80_PEEK
        and     #$7F
.endmacro

; Encoding of the buffer for the text marker: bytes XOR #$A0 give these
; screen codes. For details, see section 3.9 of DESIGN.
S80_TEXTENC     = 1
