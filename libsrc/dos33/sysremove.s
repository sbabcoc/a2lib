;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; unsigned char __fastcall__ _sysremove (const char* name);
;
; Replaces libsrc/apple2/sysremove.s from cc65. remove() passes the result
; to ___mappederrno, so it returns 0 or an __oserror value (DESIGN.md
; 5.6). As under ProDOS, a locked file fails with EACCES, and
; an open file with EINVAL (DESIGN.md 5.5a).
;

        .export         __sysremove

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

__sysremove:
        sta     name
        stx     name+1

        jsr     fm_getfcb
        bcs     done
        jsr     fm_begin
        lda     name
        ldx     name+1
        jsr     fm_name
        bcs     free
        jsr     fm_isopen       ; An open file can't be deleted
        bcs     free
        jsr     fm_begin
        lda     name
        ldx     name+1
        jsr     fm_name
        bcs     free
        lda     #FMC_DELETE
        jsr     fm_simple
        bcc     free            ; A = 0
        jsr     fm_maperr
free:   jsr     fm_freefcb      ; Preserves A
done:   ldx     #$00
        rts

        .bss

name:   .res    2
