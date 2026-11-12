;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; unsigned char __fastcall__ _sysremove (const char* name);
;
; Replaces libsrc/apple2/sysremove.s from cc65. remove() passes the result
; to ___mappederrno, so it returns 0 or a ProDOS-equivalent error code
; (DESIGN.md 5.6). A locked file fails with EACCES, as under ProDOS.
;

        .export         __sysremove
        .import         __dos_type

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

__sysremove:
        sta     name
        stx     name+1

        ; Under ProDOS the page 3 vectors aren't the File Manager
        lda     __dos_type
        beq     :+
        lda     #$01            ; ProDOS "Bad system call number" -> ENOSYS
        rts

:       jsr     fm_tempfcb
        bcs     done
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
