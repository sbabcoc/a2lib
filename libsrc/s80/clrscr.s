;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; void clrscr (void);
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/clrscr.s. Clears the VideoTerm's screen, or the model's
; 80 x 24 screen (s80.s), and homes the cursor.
;

        .export         _clrscr

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

_clrscr:
        bit     vt_active
        bmi     :+
        jmp     s80_clear
:       lda     #$0C
        jmp     vt_write
