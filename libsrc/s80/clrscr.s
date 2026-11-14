;
; void clrscr (void);
;
; 80 x 24 backends (apple2-dos33-vtwin.lib, apple2-dos33-vts70.lib), based
; on cc65's libsrc/apple2/clrscr.s. Clears the VideoTerm's screen, or the
; model's 80 x 24 screen (s80.s), and homes the cursor.
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
