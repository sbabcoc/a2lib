;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-14
;
; gotoy() for the Soft-70 library: the same column, 79 while a wrap is
; pending, on a new row. For details, see section 3.8 of DESIGN.
;

        .export         _gotoy

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; Move the cursor to a row, keeping its column (79 while a wrap is pending).
;
; Signature:    void __fastcall__ gotoy (unsigned char y)
; Overrides:    cc65's gotoy()
; Input:        A             unsigned char
;                                       y: the row, 0-23
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
