;
; unsigned char wherex (void);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/wherex.s. The cursor's column, 0-79 (79 while a wrap is
; pending).
;

        .export         _wherex

        .include        "win.inc"
        .include        "vt.inc"

_wherex:
        lda     win_x
        bit     vt_active
        bpl     :+
        lda     VT_CHORZ
:       cmp     #WIN_COLS
        bcc     :+
        lda     #WIN_COLS-1
:       ldx     #>$0000
        rts
