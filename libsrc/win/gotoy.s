;
; void __fastcall__ gotoy (unsigned char y);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/gotoy.s. Same column (79 while a wrap is pending), new row.
;

        .export         _gotoy

        .include        "win.inc"
        .include        "vt.inc"

_gotoy:
        bit     vt_active
        bpl     :++
        ldx     VT_CHORZ
        cpx     #VT_COLS
        bcc     :+
        ldx     #VT_COLS-1
:       jmp     vt_goto
:       ldx     win_x
        cpx     #WIN_COLS
        bcc     :+
        ldx     #WIN_COLS-1
:       jmp     win_goto
