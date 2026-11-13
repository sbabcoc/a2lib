;
; void __fastcall__ cputcxy (unsigned char x, unsigned char y, char c);
; void __fastcall__ cputc (char c);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/cputc.s (Ullrich von Bassewitz). With a VideoTerm, as in
; apple2-dos33-vt.lib; otherwise the 80 x 24 window (DESIGN.md 3.6).
; Character handling follows the stock module: uppercase on a II+, INVFLG
; (revers) applied, controls shown as their letters (screen codes
; $80-$9F).
;
; The implementation of cputs() relies on cputc() not clobbering ptr1;
; chline relies on cputdirect() not clobbering tmp1 and tmp2.
;

        .export         _cputcxy, _cputc
        .export         cputdirect, newline, putchar, putchardirect
        .import         gotoxy, uppercasemask

        .include        "apple2.inc"
        .include        "win.inc"
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
        jmp     win_cr
:       cmp     #$0A            ; Line feed
        beq     newline
        eor     #$80            ; Screen code
        cmp     #$E0            ; Lowercase: uppercase on a II+
        bcc     cputdirect
        and     uppercasemask

cputdirect:
        bit     vt_active
        bmi     vtdirect
        and     INVFLG          ; Normal or inverse
        jmp     win_put

newline:
        bit     vt_active
        bmi     vtnewline
        jmp     win_lf

putchar:
        bit     vt_active
        bmi     vtput
        and     INVFLG
        jmp     win_putnoadv

putchardirect:
        bit     vt_active
        bmi     vtput
        jmp     win_putnoadv

; ------------------------------------------------------------------------
; VideoTerm, as in apple2-dos33-vt.lib's cputc.s

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
