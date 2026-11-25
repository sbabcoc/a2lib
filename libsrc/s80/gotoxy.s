;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; gotoxy() and gotox() for the Soft-70 library: the VideoTerm's cursor, or the
; 80 x 24 model's. As on the VideoTerm, a column or row out of range is
; ignored. For details, see section 3.8 of DESIGN.
;

        .export         gotoxy, _gotoxy, _gotox
        .import         popa

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; gotoxy for other library modules, such as cputcxy: both coordinates on the C
; stack.
;
; Overrides:    cc65's gotoxy
; Input:        C stack       unsigned char
;                                       x
;               C stack       unsigned char
;                                       y, pushed last
; Changes:      As _gotoxy. Pops y.

gotoxy:
        jsr     popa            ; Get Y

;-----------------------------------------------------------------------------
; Move the cursor. An out-of-range column or row is ignored. Moving the cursor
; doesn't pan; writing or showing it does.
;
; Signature:    void __fastcall__ gotoxy (unsigned char x, unsigned char y)
; Overrides:    cc65's gotoxy()
; Input:        C stack       unsigned char
;                                       x: the column, 0-79
;               A             unsigned char
;                                       y: the row, 0-23
; Changes:      A, X, Y and flags; the cursor. Pops x.

_gotoxy:
        pha                     ; Row
        jsr     popa            ; Column
        tax
        pla
        bit     vt_active
        bpl     :+
        jmp     vt_goto
:       jmp     s80_goto

;-----------------------------------------------------------------------------
; Move the cursor to a column of its row.
;
; Signature:    void __fastcall__ gotox (unsigned char x)
; Overrides:    cc65's gotox()
; Input:        A             unsigned char
;                                       x: the column, 0-79
; Changes:      A, X and flags; the cursor.

_gotox:
        tax                     ; Column; same row
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
        jmp     vt_goto
:       lda     s80_y
        jmp     s80_goto
