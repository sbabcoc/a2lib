;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; cputc(), cputcxy() and the routines other conio functions write with, for
; the VideoTerm library. While the card is in use, each writes through the
; firmware in place of the stock screen. None of the card's paths change ptr1.
;
; Important note: The implementation of cputs() relies on the cputc() function
; not clobbering ptr1. Beware when rewriting or changing this function!
;
; For details, see section 3.4 of DESIGN.
;

        .constructor    initconio
        .export         _cputcxy, _cputc
        .export         cputdirect, newline, putchar, putchardirect
        .import         gotoxy, VTABZ

        .ifndef __APPLE2ENH__
        .import         machinetype
        .import         uppercasemask
        .endif

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "apple2.inc"
        .include        "vt.inc"

        .segment        "ONCE"

;-----------------------------------------------------------------------------
; The module constructor, as stock's: on a IIe or later, the alternate
; character set, and SET80COL-HISCR limited to text.
;
; Overrides:    cc65's initconio
; Changes:      A and flags; the soft switches.

initconio:
        .ifndef __APPLE2ENH__
        bit     machinetype
        bmi     :+
        rts
:
        .endif
        sta     SETALTCHAR      ; Switch in alternate charset
        bit     LORES           ; Limit SET80COL-HISCR to text
        rts

        .code

;-----------------------------------------------------------------------------
; Move the cursor, then write a character.
;
; Signature:    void __fastcall__ cputcxy (unsigned char x, unsigned char y,
;               char c)
; Overrides:    cc65's cputcxy()
; Input:        C stack       unsigned char
;                                       x
;               C stack       unsigned char
;                                       y
;               A             char      c
; Changes:      As gotoxy and _cputc. Pops x and y.

_cputcxy:
        pha                     ; Save C
        jsr     gotoxy          ; Call this one, will pop params
        pla                     ; Restore C and run into _cputc

;-----------------------------------------------------------------------------
; Write a character at the cursor and advance. '\r' goes to column 0 and '\n'
; down a line, in the same column. On the card, other controls show as their
; letters, as screen codes $80-$9F do, and INVFLG (revers) has no effect.
;
; Signature:    void __fastcall__ cputc (char c)
; Overrides:    cc65's cputc()
; Input:        A             char      c
; Changes:      A, X, Y and flags; the screen and the cursor. On the 40-column
;               screen: tmp3, and BASL/BASH at a new line (VTABZ). Not ptr1,
;               which cputs keeps a pointer in.

_cputc:
        bit     vt_active
        jmi     vtcputc
        cmp     #$0D            ; Test for \r = carriage return
        beq     left
        cmp     #$0A            ; Test for \n = line feed
        beq     newline
        eor     #$80            ; Invert high bit
        .ifndef __APPLE2ENH__
        cmp     #$E0            ; Test for lowercase
        bcc     cputdirect
        and     uppercasemask
        .endif

;-----------------------------------------------------------------------------
; Write a screen code at the cursor and advance.
;
; Overrides:    cc65's cputdirect
; Input:        A             byte      the screen code
; Changes:      As _cputc.

cputdirect:
        bit     vt_active
        jmi     vtdirect
        jsr     putchar

        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     :+
        .endif
        bit     RD80VID         ; In 80 column mode?
        bpl     :+
        inc     OURCH           ; Bump to next column
        lda     OURCH
        .ifdef __APPLE2ENH__
        bra     check           ; Must leave CH alone
        .else
        jmp     check
        .endif

:       inc     CH              ; Bump to next column
        lda     CH
check:  cmp     WNDWDTH
        bcc     done
        jsr     newline
left:
        .ifdef  __APPLE2ENH__
        stz     CH              ; Goto left edge of screen
        .else
        lda     #$00
        sta     CH
        .endif

        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     done
        .endif

        bit     RD80VID         ; In 80 column mode?
        bpl     done
        .ifdef  __APPLE2ENH__
        stz     OURCH           ; Goto left edge of screen
        .else
        sta     OURCH
        .endif

done:   rts

;-----------------------------------------------------------------------------
; Move the cursor down a line, in the same column. On the 40-column screen,
; the bottom line wraps to the window's top.
;
; Overrides:    cc65's newline
; Changes:      A and flags; the cursor. On the 40-column screen: CV and
;               BASL/BASH (VTABZ).

newline:
        bit     vt_active
        jmi     vtnewline
        inc     CV              ; Bump to next line
        lda     CV
        cmp     WNDBTM
        bcc     :+
        lda     WNDTOP          ; Goto top of screen
        sta     CV
:       jmp     VTABZ

;-----------------------------------------------------------------------------
; Store a character at the cursor, without advancing, as INVFLG shows it. On
; the card, INVFLG has no effect.
;
; Overrides:    cc65's putchar
; Input:        A             byte      the screen code
; Changes:      As putchardirect.

putchar:
        bit     vt_active
        bmi     vtput
        cmp     #$E0            ; Lowercase?
        and     INVFLG          ; Apply normal, inverse, flash
        bcc     putchardirect   ; Not lowercase, no special handling
        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     putchardirect   ; Mask normally for ][/+ ; done
        .endif
        ora     #$40            ; Restore lowercase bit for //e and up

;-----------------------------------------------------------------------------
; Store a screen code at the cursor, without advancing. On the card: write it,
; then backspace.
;
; Overrides:    cc65's putchardirect
; Input:        A             byte      the screen code
; Output:       tmp3          byte      on the 40-column screen: the character
;                                       it replaced, for cgetc
; Changes:      A, X, Y and flags; the screen.

putchardirect:
        bit     vt_active
        bmi     vtput
        tax
        ldy     CH

        sec                     ; Assume main memory

        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     put
        .endif

        bit     RD80VID         ; In 80 column mode?
        bpl     put             ; No, just go ahead
        lda     OURCH
        lsr                     ; Div by 2
        tay
        bcs     put             ; Odd cols go in main memory
        php
        sei                     ; No valid MSLOT et al. in aux memory
        bit     HISCR           ; Assume SET80COL

put:    lda     (BASL),Y        ; Get current character
        sta     tmp3            ; Save old character for _cgetc
        txa
        sta     (BASL),Y

        bcs     :+              ; In main memory
        bit     LOWSCR
        plp
:       rts

; ------------------------------------------------------------------------
; VideoTerm

;-----------------------------------------------------------------------------
; _cputc on the card.
;
; Input:        A             char      c
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
; cputdirect on the card.
;
; Input:        A             byte      the screen code
; Changes:      A and flags; the screen and the cursor.

vtdirect:
        jsr     vt_screen
        jmp     vt_write

;-----------------------------------------------------------------------------
; newline on the card: a line feed.
;
; Changes:      A and flags; the cursor.

vtnewline:
        lda     #$8A            ; Line feed
        jmp     vt_write

;-----------------------------------------------------------------------------
; putchar and putchardirect on the card.
;
; Input:        A             byte      the screen code
; Changes:      A and flags; the screen.

vtput:  jsr     vt_screen
        jsr     vt_write
        lda     #$88            ; Backspace
        jmp     vt_write
