;
; Ullrich von Bassewitz, 06.08.1998
;
; void __fastcall__ gotoy (unsigned char y);
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/gotoy.s from cc65; if the card is in use, moves its cursor
; with the firmware's GOTOXY instead.
; (DESIGN.md 3.4).

        .export         _gotoy
        .import         VTABZ
        .include        "vt.inc"

        .include        "apple2.inc"

_gotoy:
        bit     vt_active
        bmi     vty
        clc
        adc     WNDTOP
        sta     CV              ; Store Y
        jmp     VTABZ

vty:    ldx     VT_CHORZ        ; Same column (79 if a wrap is pending)
        cpx     #VT_COLS
        bcc     :+
        ldx     #VT_COLS-1
:       jmp     vt_goto
