;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; void __fastcall__ cputcxy (unsigned char x, unsigned char y, char c);
; void __fastcall__ cputc (char c);
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/cputc.s (Ullrich von Bassewitz). With a VideoTerm, as in
; a2lib-vt.lib; otherwise the model (s80.s). Character handling follows the
; stock module: uppercase unless the display shows lowercase
; (uppercasemask), INVFLG (revers) applied by S80_ATTR (display.inc),
; controls shown as their letters (screen codes $80-$9F).
;
; The implementation of cputs() relies on cputc() not clobbering ptr1;
; chline relies on cputdirect() not clobbering tmp1 and tmp2.
;

        .export         _cputcxy, _cputc
        .export         cputdirect, newline, putchar, putchardirect
        .import         gotoxy, uppercasemask

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; _cputcxy: Move the cursor, then write a character: void __fastcall__ cputcxy
; (unsigned char x, unsigned char y, char c).
;
; Input:        C stack       unsigned char
;                                       x
;               C stack       unsigned char
;                                       y
;               A             char      c
; Output:       none
; Changes:      As gotoxy and _cputc. Pops x and y.

_cputcxy:
        pha                     ; Save C
        jsr     gotoxy          ; Call this one, will pop params
        pla                     ; Restore C and run into _cputc

;-----------------------------------------------------------------------------
; _cputc: Write a character at the cursor and advance: void __fastcall__ cputc
; (char c). '\r' goes to column 0 and '\n' down a line, in the same column;
; other controls show as their letters.
;
; Input:        A             char      c
; Output:       none
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
; cputdirect: Write a screen code at the cursor and advance, as INVFLG shows
; it.
;
; Input:        A             byte      the screen code
; Output:       none
; Changes:      As _cputc. chline keeps counters in tmp1 and tmp2 across it.

cputdirect:
        bit     vt_active
        bmi     vtdirect
        S80_ATTR                ; Normal or inverse
        jmp     s80_put

;-----------------------------------------------------------------------------
; newline: Move the cursor down a line, in the same column, scrolling at the
; bottom.
;
; Input:        none
; Output:       none
; Changes:      A and flags; the cursor. In the model, on a scroll: X, Y,
;               BASL, BAS2L, the buffer and the display.

newline:
        bit     vt_active
        bmi     vtnewline
        jmp     s80_lf

;-----------------------------------------------------------------------------
; putchar: Store a screen code at the cursor, without advancing, as INVFLG
; shows it.
;
; Input:        A             byte      the screen code
; Output:       none
; Changes:      As putchardirect.

putchar:
        bit     vt_active
        bmi     vtput
        S80_ATTR
        jmp     s80_putnoadv

;-----------------------------------------------------------------------------
; putchardirect: Store a screen code at the cursor, without advancing. On the
; VideoTerm: write it, then backspace.
;
; Input:        A             byte      the screen code
; Output:       none
; Changes:      A, X, Y and flags; the screen; in the model, BASL and BAS2L.

putchardirect:
        bit     vt_active
        bmi     vtput
        jmp     s80_putnoadv

; ------------------------------------------------------------------------
; VideoTerm, as in a2lib-vt.lib's cputc.s


;-----------------------------------------------------------------------------
; vtcputc: _cputc on the VideoTerm.
;
; Input:        A             char      c
; Output:       none
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
; vtdirect: cputdirect on the VideoTerm.
;
; Input:        A             byte      the screen code
; Output:       none
; Changes:      A and flags; the screen and the cursor.

vtdirect:
        jsr     vt_screen
        jmp     vt_write

;-----------------------------------------------------------------------------
; vtnewline: newline on the VideoTerm: a line feed.
;
; Input:        none
; Output:       none
; Changes:      A and flags; the cursor.

vtnewline:
        lda     #$8A            ; Line feed
        jmp     vt_write

;-----------------------------------------------------------------------------
; vtput: putchar and putchardirect on the VideoTerm.
;
; Input:        A             byte      the screen code
; Output:       none
; Changes:      A and flags; the screen.

vtput:  jsr     vt_screen
        jsr     vt_write
        lda     #$88            ; Backspace
        jmp     vt_write
