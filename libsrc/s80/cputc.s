;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; void __fastcall__ cputcxy (unsigned char x, unsigned char y, char c);
; void __fastcall__ cputc (char c);
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
; on cc65's libsrc/apple2/cputc.s (Ullrich von Bassewitz). With a
; VideoTerm, as in a2lib-vt.lib; otherwise the model (s80.s).
; Character handling follows the stock module: uppercase unless the
; display shows lowercase (uppercasemask), INVFLG (revers) applied by
; S80_ATTR (display.inc), controls shown as their letters (screen codes
; $80-$9F).
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

_cputcxy:
        pha                     ; Save C
        jsr     gotoxy          ; Call this one, will pop params
        pla                     ; Restore C and run into _cputc

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

cputdirect:
        bit     vt_active
        bmi     vtdirect
        S80_ATTR                ; Normal or inverse
        jmp     s80_put

newline:
        bit     vt_active
        bmi     vtnewline
        jmp     s80_lf

putchar:
        bit     vt_active
        bmi     vtput
        S80_ATTR
        jmp     s80_putnoadv

putchardirect:
        bit     vt_active
        bmi     vtput
        jmp     s80_putnoadv

; ------------------------------------------------------------------------
; VideoTerm, as in a2lib-vt.lib's cputc.s

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
