;
; Scott Babcock, 2026-11-12
;
; remove() for DOS 3.3 files. As under ProDOS, a locked file fails with
; EACCES, and an open file with EINVAL. For details, see section 5.5 of
; DESIGN.
;

        .export         __sysremove

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

;-----------------------------------------------------------------------------
; Delete a file, for remove().
;
; Signature:    unsigned char __fastcall__ _sysremove (const char* name)
; Overrides:    cc65's _sysremove()
; Input:        AX            char*     name: the file's path
; Output:       A             byte      0, or the __oserror value:
;                                       DOSERR_LOCKED (EACCES) for a locked
;                                       file, LIBERR_OPEN (EINVAL) for an open
;                                       one, DOSERR_NOBUFS (ENOMEM) with no
;                                       free DOS buffer, DOSERR_SYNTAX
;                                       (EINVAL) for a bad path, or another
;                                       DOS 3.3 error
; Changes:      X and Y; ptr1 (fm_name), ptr2 (fm_isopen), fm_parmlist and
;               ctlblock. Takes a DOS buffer for the call and releases it.
; Note:         X isn't set: the only caller, cc65's remove(),
;               ends in ___mappederrno, which sets it.

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
done:   rts

        .bss

name:   .res    2               ; char*: the file's path
