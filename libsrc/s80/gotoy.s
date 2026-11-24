;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-14
;
; void __fastcall__ gotoy (unsigned char y);
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/gotoy.s. Same column (79 while a wrap is pending), new row.
;

        .export         _gotoy

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; _gotoy: Move the cursor to a row, keeping its column (79 while a wrap is
; pending): void __fastcall__ gotoy (unsigned char y).
;
; Input:        A             unsigned char
;                                       y: the row, 0-23
; Output:       none
; Changes:      X and flags; the cursor. On the VideoTerm: A.

_gotoy:
        bit     vt_active
        bpl     model
        ldx     VT_CHORZ
        cpx     #VT_COLS
        bcc     :+
        ldx     #VT_COLS-1
:       jmp     vt_goto
model:  ldx     s80_x
        cpx     #S80_COLS
        bcc     :+
        ldx     #S80_COLS-1
:       jmp     s80_goto
