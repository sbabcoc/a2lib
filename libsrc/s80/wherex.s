;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; unsigned char wherex (void);
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/wherex.s. The cursor's column, 0-79 (79 while a wrap is
; pending).
;

        .export         _wherex

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; _wherex: The cursor's column, 0-79 (79 while a wrap is pending): unsigned
; char wherex (void).
;
; Input:        none
; Output:       AX            unsigned char
;                                       the column
; Changes:      Flags. Y is unchanged.

_wherex:
        lda     s80_x
        bit     vt_active
        bpl     :+
        lda     VT_CHORZ
:       cmp     #S80_COLS
        bcc     :+
        lda     #S80_COLS-1
:       ldx     #>$0000
        rts
