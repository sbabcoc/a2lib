;
; void clrscr (void);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/clrscr.s. Clears the VideoTerm's screen, or the window's
; 80 x 24 screen, and homes the cursor.
;

        .export         _clrscr

        .include        "win.inc"
        .include        "vt.inc"

_clrscr:
        bit     vt_active
        bmi     :+
        jmp     win_clear
:       lda     #$0C
        jmp     vt_write
