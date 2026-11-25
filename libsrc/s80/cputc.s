;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; cputc(), cputcxy() and the routines other conio functions write with, for
; the Soft-70 library: to the VideoTerm, as in the VideoTerm library, or into
; the 80 x 24 model. Characters are handled as cc65's are: uppercase unless
; the display shows lowercase, INVFLG applied, and controls shown as their
; letters.
;
; cputs() relies on cputc() not changing ptr1, and chline() on cputdirect()
; not changing tmp1 and tmp2. For details, see section 3.8 of DESIGN.
;

        .export         _cputcxy, _cputc
        .export         cputdirect, newline, putchar, putchardirect
        .import         gotoxy, uppercasemask

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; Move the cursor, then write a character.
;
; Signature:    void __fastcall__ cputcxy (unsigned char x, unsigned char y,
;               char c)
; Overrides:    cc65's cputcxy()
; Input:        C stack       unsigned char
;                                       column
;               C stack       unsigned char
;                                       row
;               A             char      character
; Changes:      As gotoxy and _cputc. Pops x and y.

_cputcxy:
        pha                     ; Save C
        jsr     gotoxy          ; Call this one, will pop params
        pla                     ; Restore C and run into _cputc

;-----------------------------------------------------------------------------
; Write a character at the cursor and advance. '\r' goes to column 0 and '\n'
; down a line, in the same column; other controls show as their letters.
;
; Signature:    void __fastcall__ cputc (char c)
; Overrides:    cc65's cputc()
; Input:        A             char      character
; Changes:      A, X, Y and flags; the screen and the cursor; in the model,
;               BASL and BAS2L. Not ptr1, tmp1 or tmp2.

_cputc:
        bit     vt_active
        bmi     vtcputc
        cmp     #$0D            ; Carriage return
        bne     :+
        jmp     s80_cr
:       cmp     #$0A            ; Line feed
        beq     newline
        eor     #$80            ; Screen code
        cmp     #$E0            ; Lowercase: uppercase on a II+
        bcc     cputdirect
        and     uppercasemask

;-----------------------------------------------------------------------------
; Write a screen code at the cursor and advance, as INVFLG shows it.
;
; Overrides:    cc65's cputdirect
; Input:        A             byte      the screen code
; Changes:      As _cputc. chline keeps counters in tmp1 and tmp2 across it.

cputdirect:
        bit     vt_active
        bmi     vtdirect
        S80_ATTR                ; Normal or inverse
        jmp     s80_put

;-----------------------------------------------------------------------------
; Move the cursor down a line, in the same column, scrolling at the bottom.
;
; Overrides:    cc65's newline
; Changes:      A and flags; the cursor. In the model, on a scroll: X, Y,
;               BASL, BAS2L, the buffer and the display.

newline:
        bit     vt_active
        bmi     vtnewline
        jmp     s80_lf

;-----------------------------------------------------------------------------
; Store a screen code at the cursor, without advancing, as INVFLG shows it.
;
; Overrides:    cc65's putchar
; Input:        A             byte      the screen code
; Changes:      As putchardirect.

putchar:
        bit     vt_active
        bmi     vtput
        S80_ATTR
        jmp     s80_putnoadv

;-----------------------------------------------------------------------------
; Store a screen code at the cursor, without advancing. On the VideoTerm:
; write it, then backspace.
;
; Overrides:    cc65's putchardirect
; Input:        A             byte      the screen code
; Changes:      A, X, Y and flags; the screen; in the model, BASL and BAS2L.

putchardirect:
        bit     vt_active
        bmi     vtput
        jmp     s80_putnoadv

; ------------------------------------------------------------------------
; VideoTerm, as in the VideoTerm library


;-----------------------------------------------------------------------------
; _cputc on the VideoTerm.
;
; Input:        A             char      character
; Changes:      A and flags; the screen and the cursor.

vtcputc:
        cmp     #$0D            ; CR only
        beq     vtw
        cmp     #$0A            ; Line feed, same column
        beq     vtnewline
        and     #$7F
        cmp     #$20
        bcs     vtw
        ora     #$40            ; Controls show as their letters
vtw:    jmp     vt_write

;-----------------------------------------------------------------------------
; cputdirect on the VideoTerm.
;
; Input:        A             byte      the screen code
; Changes:      A and flags; the screen and the cursor.

vtdirect:
        jsr     vt_screen
        jmp     vt_write

;-----------------------------------------------------------------------------
; newline on the VideoTerm: a line feed.
;
; Changes:      A and flags; the cursor.

vtnewline:
        lda     #$8A            ; Line feed
        jmp     vt_write

;-----------------------------------------------------------------------------
; putchar and putchardirect on the VideoTerm.
;
; Input:        A             byte      the screen code
; Changes:      A and flags; the screen.

vtput:  jsr     vt_screen
        jsr     vt_write
        lda     #$88            ; Backspace
        jmp     vt_write
