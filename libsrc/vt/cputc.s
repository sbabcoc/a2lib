;
; Ullrich von Bassewitz, 06.08.1998
;
; void __fastcall__ cputcxy (unsigned char x, unsigned char y, char c);
; void __fastcall__ cputc (char c);
;
; Important note: The implementation of cputs() relies on the cputc() function
; not clobbering ptr1. Beware when rewriting or changing this function!
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/cputc.s from cc65. Each exported entry point first tests
; vt_active; if the card is in use, it writes through the firmware instead
; of the 40-column screen (DESIGN.md 3.4):
;   cputc:          '\r' -> CR only, '\n' -> line feed (same column); other
;                   controls show as their letters, as screen codes
;                   $80-$9F do
;   cputdirect:     screen code, advancing
;   putchar,
;   putchardirect:  screen code, not advancing (write, then backspace)
;   newline:        line feed
; INVFLG (revers) has no effect on the card (DESIGN.md 3.4).
; None of the VideoTerm paths change ptr1.

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

; Plot a character - also used as internal function

_cputcxy:
        pha                     ; Save C
        jsr     gotoxy          ; Call this one, will pop params
        pla                     ; Restore C and run into _cputc

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

vtdirect:
        jsr     vt_screen
        jmp     vt_write

vtnewline:
        lda     #$8A            ; Line feed
        jmp     vt_write

vtput:  jsr     vt_screen
        jsr     vt_write
        lda     #$88            ; Backspace
        jmp     vt_write
