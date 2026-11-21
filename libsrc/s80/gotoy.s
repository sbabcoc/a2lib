;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-14
;
; void __fastcall__ gotoy (unsigned char y);
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
; on cc65's libsrc/apple2/gotoy.s. Same column (79 while a wrap is
; pending), new row.
;

        .export         _gotoy

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

_gotoy:
        bit     vt_active
        bpl     :++
        ldx     VT_CHORZ
        cpx     #VT_COLS
        bcc     :+
        ldx     #VT_COLS-1
:       jmp     vt_goto
:       ldx     s80_x
        cpx     #S80_COLS
        bcc     :+
        ldx     #S80_COLS-1
:       jmp     s80_goto
