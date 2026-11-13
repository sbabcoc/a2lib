;
; unsigned char wherey (void);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/wherey.s. The cursor's row.
;

        .export         _wherey

        .include        "win.inc"
        .include        "vt.inc"

_wherey:
        lda     win_y
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
:       ldx     #>$0000
        rts
