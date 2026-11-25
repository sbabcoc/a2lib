;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; gotoy() for the VideoTerm library: on the card, with the firmware's GOTOXY.
; For details, see section 3.4 of DESIGN.
;

        .export         _gotoy
        .import         VTABZ
        .include        "vt.inc"

        .include        "apple2.inc"

;-----------------------------------------------------------------------------
; Move the cursor to a row, keeping its column. On the card, column 79 if a
; wrap is pending.
;
; Signature:    void __fastcall__ gotoy (unsigned char y)
; Overrides:    cc65's gotoy()
; Input:        A             unsigned char
;                                       row, from the top of the window
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
