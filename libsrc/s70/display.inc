;
; Soft-70: parameters of the shared 80 x 24 model (s80.inc)
;
; Soft-70 shows 70 of the 80 columns on hi-res page 1, panning between
; columns 0-69 and 10-79 (DESIGN.md 3.8). The buffer is outside BSS, below
; the hi-res page, so that it doesn't take space from the program.
;

S80_VIEW        = 70
S80_STEP        = 10
.define         S80_API         "_s70_"
.define         S80_BUFSEG      "LOWBSS"

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
