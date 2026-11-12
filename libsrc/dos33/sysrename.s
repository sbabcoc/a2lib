;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; unsigned char __fastcall__ _sysrename (const char* oldname, const char* newname);
;
; Replaces libsrc/apple2/sysrename.s from cc65. rename() passes the result
; to ___mappederrno, so it returns 0 or a ProDOS-equivalent error code.
;
;   - The old name may carry suffixes (",S6,D2,V254"); the new name may
;     not, since the file stays where it is. A new name with a suffix
;     fails with EINVAL.
;   - DOS's RENAME doesn't check whether the new name is already in use
;     and would leave two files with the same name. As under ProDOS, an
;     existing new name fails with EEXIST.
;   - A locked file fails with EACCES, as under ProDOS.
;
; See DESIGN.md 5.5.
;

        .export         __sysrename
        .import         __dos_type
        .import         popax

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

__sysrename:
        sta     newname
        stx     newname+1
        jsr     popax
        sta     oldname
        stx     oldname+1

        ; Under ProDOS the page 3 vectors aren't the File Manager
        lda     __dos_type
        beq     :+
        lda     #$01            ; ProDOS "Bad system call number" -> ENOSYS
        rts

        ; The new name takes no suffixes
:       lda     newname
        sta     ptr1
        lda     newname+1
        sta     ptr1+1
        ldy     #$00
:       lda     (ptr1),y
        beq     :+
        cmp     #','
        beq     badname
        iny
        bne     :-
badname:
        lda     #$40            ; ProDOS "Invalid pathname" -> EINVAL
        rts

:       jsr     fm_tempfcb
        bcs     done
        jsr     fm_begin

        ; Parse the new name and keep it
        lda     newname
        ldx     newname+1
        jsr     fm_name
        bcs     free
        ldx     #30-1
:       lda     fm_namebuf,x
        sta     newbuf,x
        dex
        bpl     :-

        ; Parse the old name: sets the name, volume, drive and slot
        lda     oldname
        ldx     oldname+1
        jsr     fm_name
        bcs     free

        ; Refuse a new name that's in use: OPEN it without allocating
        lda     #<newbuf
        ldx     #>newbuf
        jsr     setname
        lda     #$00
        ldy     #FM_RECORD
        sta     (ptr3),y
        iny
        sta     (ptr3),y
        ldy     #FM_CALL
        lda     #FMC_OPEN
        sta     (ptr3),y
        ldx     #$01
        jsr     fm_call
        bcs     :+
        lda     #FMC_CLOSE      ; It exists
        jsr     fm_simple
        lda     #$47            ; ProDOS "Duplicate filename" -> EEXIST
        bne     free            ; Branch always
:       cmp     #FMR_NOTFOUND
        bne     fmerr

        ; RENAME: old name at FM_NAME, new name at FM_NEWNAME
        lda     #<fm_namebuf
        ldx     #>fm_namebuf
        jsr     setname
        ldy     #FM_NEWNAME
        lda     #<newbuf
        sta     (ptr3),y
        iny
        lda     #>newbuf
        sta     (ptr3),y
        lda     #FMC_RENAME
        jsr     fm_simple
        bcc     free            ; A = 0
fmerr:  jsr     fm_maperr
free:   jsr     fm_freefcb      ; Preserves A
done:   ldx     #$00
        rts

; setname: point FM_NAME at the 30-byte name buffer in AX.

setname:
        ldy     #FM_NAME
        sta     (ptr3),y
        iny
        txa
        sta     (ptr3),y
        rts

        .bss

oldname:        .res    2
newname:        .res    2
newbuf:         .res    30
