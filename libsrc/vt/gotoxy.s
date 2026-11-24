;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; void __fastcall__ gotoxy (unsigned char x, unsigned char y);
; void __fastcall__ gotox (unsigned char x);
;
;
; VideoTerm backend (a2lib-vt.lib): modified copy of libsrc/apple2/gotoxy.s
; from cc65; if the card is in use, moves its cursor with the firmware's
; GOTOXY instead (DESIGN.md 3.4).

        .export         gotoxy, _gotoxy, _gotox
        .import         popa, VTABZ
        .include        "vt.inc"

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .include        "apple2.inc"

;-----------------------------------------------------------------------------
; gotoxy: gotoxy for other library modules, such as cputcxy: both coordinates
; on the C stack.
;
; Input:        C stack       unsigned char
;                                       x
;               C stack       unsigned char
;                                       y, pushed last
; Output:       none
; Changes:      As _gotoxy. Pops x and y.

gotoxy:
        jsr     popa            ; Get Y

;-----------------------------------------------------------------------------
; _gotoxy: Move the cursor: void __fastcall__ gotoxy (unsigned char x,
; unsigned char y). On the card, with the firmware's GOTOXY.
;
; Input:        C stack       unsigned char
;                                       x: the column
;               A             unsigned char
;                                       y: the row, from the top of the window
; Output:       none
; Changes:      A, X, Y and flags; the cursor; on the 40-column screen, CV and
;               BASL/BASH (VTABZ). Pops x.

_gotoxy:
        bit     vt_active
        bmi     vtxy
        clc
        adc     WNDTOP
        sta     CV              ; Store Y
        jsr     VTABZ
        jsr     popa            ; Get X

;-----------------------------------------------------------------------------
; _gotox: Move the cursor to a column of its row: void __fastcall__ gotox
; (unsigned char x).
;
; Input:        A             unsigned char
;                                       x: the column
; Output:       none
; Changes:      Flags; the cursor. On the card: A and X.

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
