;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; unsigned char wherey (void);
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
; on cc65's libsrc/apple2/wherey.s. The cursor's row.
;

        .export         _wherey

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

_wherey:
        lda     s80_y
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
:       ldx     #>$0000
        rts
