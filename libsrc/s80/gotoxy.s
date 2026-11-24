;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; void __fastcall__ gotoxy (unsigned char x, unsigned char y);
; void __fastcall__ gotox (unsigned char x);
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/gotoxy.s. With a VideoTerm, firmware GOTOXY; otherwise the
; model's cursor. As on the VideoTerm, an out-of-range column or row is
; ignored. Moving the cursor doesn't pan; writing or showing it does
; (DESIGN.md 3.6).
;

        .export         gotoxy, _gotoxy, _gotox
        .import         popa

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; gotoxy: gotoxy for other library modules, such as cputcxy: both coordinates
; on the C stack.
;
; Input:        C stack       unsigned char
;                                       x
;               C stack       unsigned char
;                                       y, pushed last
; Output:       none
; Changes:      As _gotoxy. Pops y.

gotoxy:
        jsr     popa            ; Get Y

;-----------------------------------------------------------------------------
; _gotoxy: Move the cursor: void __fastcall__ gotoxy (unsigned char x,
; unsigned char y). An out-of-range column or row is ignored. Moving the
; cursor doesn't pan; writing or showing it does.
;
; Input:        C stack       unsigned char
;                                       x: the column, 0-79
;               A             unsigned char
;                                       y: the row, 0-23
; Output:       none
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
; _gotox: Move the cursor to a column of its row: void __fastcall__ gotox
; (unsigned char x).
;
; Input:        A             unsigned char
;                                       x: the column, 0-79
; Output:       none
; Changes:      A, X and flags; the cursor.

_gotox:
        tax                     ; Column; same row
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
        jmp     vt_goto
:       lda     s80_y
        jmp     s80_goto
