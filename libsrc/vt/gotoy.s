;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; void __fastcall__ gotoy (unsigned char y);
;
;
; VideoTerm backend (a2lib-vt.lib): modified copy of libsrc/apple2/gotoy.s
; from cc65; if the card is in use, moves its cursor with the firmware's
; GOTOXY instead (DESIGN.md 3.4).

        .export         _gotoy
        .import         VTABZ
        .include        "vt.inc"

        .include        "apple2.inc"

;-----------------------------------------------------------------------------
; _gotoy: Move the cursor to a row, keeping its column: void __fastcall__
; gotoy (unsigned char y). On the card, column 79 if a wrap is pending.
;
; Input:        A             unsigned char
;                                       y: the row, from the top of the window
; Output:       none
; Changes:      A and flags; the cursor. On the card: X. Otherwise: CV and
;               BASL/BASH (VTABZ).

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
