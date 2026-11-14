;
; void __fastcall__ gotoy (unsigned char y);
;
; 80 x 24 backends (apple2-dos33-vtwin.lib, apple2-dos33-vts70.lib), based
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
