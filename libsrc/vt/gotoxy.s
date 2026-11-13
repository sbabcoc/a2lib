;
; Ullrich von Bassewitz, 06.08.1998
;
; void __fastcall__ gotoxy (unsigned char x, unsigned char y);
; void __fastcall__ gotox (unsigned char x);
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/gotoxy.s from cc65; if the card is in use, moves its cursor
; with the firmware's GOTOXY instead.
; (DESIGN.md 3.4).

        .export         gotoxy, _gotoxy, _gotox
        .import         popa, VTABZ
        .include        "vt.inc"

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .include        "apple2.inc"

gotoxy:
        jsr     popa            ; Get Y

_gotoxy:
        bit     vt_active
        bmi     vtxy
        clc
        adc     WNDTOP
        sta     CV              ; Store Y
        jsr     VTABZ
        jsr     popa            ; Get X

_gotox:
        bit     vt_active
        bmi     vtx
        sta     CH              ; Store X

        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     :+
        .endif

        bit     RD80VID         ; In 80 column mode?
        bpl     :+
        sta     OURCH           ; Store X
:       rts

vtxy:   pha                     ; Row
        jsr     popa            ; Column
        tax
        pla
        jmp     vt_goto

vtx:    tax                     ; Column; same row
        lda     VT_CVERT
        jmp     vt_goto
