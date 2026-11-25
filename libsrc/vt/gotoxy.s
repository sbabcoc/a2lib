;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; gotoxy() and gotox() for the VideoTerm library: on the card, with the
; firmware's GOTOXY. For details, see section 3.4 of DESIGN.
;

        .export         gotoxy, _gotoxy, _gotox
        .import         popa, VTABZ
        .include        "vt.inc"

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .include        "apple2.inc"

;-----------------------------------------------------------------------------
; gotoxy for other library modules, such as cputcxy: both coordinates on the C
; stack.
;
; Overrides:    cc65's gotoxy
; Input:        C stack       unsigned char
;                                       column
;               C stack       unsigned char
;                                       row, pushed last
; Changes:      As _gotoxy. Pops x and y.

gotoxy:
        jsr     popa            ; Get Y

;-----------------------------------------------------------------------------
; Move the cursor: on the card, with the firmware's GOTOXY.
;
; Signature:    void __fastcall__ gotoxy (unsigned char x, unsigned char y)
; Overrides:    cc65's gotoxy()
; Input:        C stack       unsigned char
;                                       column
;               A             unsigned char
;                                       row, from the top of the window
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
; Move the cursor to a column of its row.
;
; Signature:    void __fastcall__ gotox (unsigned char x)
; Overrides:    cc65's gotox()
; Input:        A             unsigned char
;                                       column
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
