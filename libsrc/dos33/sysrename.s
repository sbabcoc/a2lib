;
; Scott Babcock, 2026-11-12
;
; unsigned char __fastcall__ _sysrename (const char* oldname, const char* newname);
;
; Replaces libsrc/apple2/sysrename.s from cc65. rename() passes the result
; to ___mappederrno, so it returns 0 or an __oserror value (DESIGN.md 5.6).
;
;   - Either path may give the slot and drive ("/6/2/NAME", "2/NAME"),
;     but the new one must be where the old one is: DOS's RENAME can't
;     move a file. Another slot or drive fails with EINVAL (cc65 has no
;     EXDEV).
;   - DOS's RENAME doesn't check whether the new name is already in use
;     and would leave two files with the same name. As under ProDOS, an
;     existing new name fails with EEXIST.
;   - A locked file fails with EACCES, and an open file with EINVAL, as
;     under ProDOS (DESIGN.md 5.5a).
;   - A file renamed to its own name is left as it is, as POSIX says.
;
; See DESIGN.md 5.5.
;

        .export         __sysrename
        .import         popax

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

;-----------------------------------------------------------------------------
; __sysrename: Rename a file, for rename(): unsigned char __fastcall__
; _sysrename (const char* oldname, const char* newname).
;
; Input:        C stack       char*     oldname: the file's path
;               AX            char*     newname: its new path, on the same
;                                       slot and drive
; Output:       A             byte      0, or the __oserror value:
;                                       DOSERR_SYNTAX (EINVAL) for a bad path
;                                       or another slot or drive,
;                                       LIBERR_EXISTS (EEXIST) if newname is
;                                       another file's, LIBERR_OPEN (EINVAL)
;                                       for an open file, DOSERR_NOBUFS
;                                       (ENOMEM) with no free DOS buffer, or
;                                       RENAME's own error, such as
;                                       DOSERR_LOCKED (EACCES)
;               X             byte      0
; Changes:      Y; ptr1 (fm_name), ptr2 (fm_isopen), fm_parmlist and ctlblock.
;               Pops oldname. Takes a DOS buffer for the call and releases it.

__sysrename:
        sta     newname
        stx     newname+1
        jsr     popax
        sta     oldname
        stx     oldname+1

        jsr     fm_getfcb
        jcs     done
        jsr     fm_begin

        ; Parse the new name and keep it, with its slot and drive
        lda     newname
        ldx     newname+1
        jsr     fm_name
        jcs     free
        ldx     #NAME_LEN-1
:       lda     fm_namebuf,x
        sta     newbuf,x
        dex
        bpl     :-
        lda     fm_slot
        sta     newslot
        lda     fm_drive
        sta     newdrive

        ; Parse the old name: sets the name, volume, drive and slot. An
        ; open file can't be renamed; the check leaves the parameter list
        ; to be set up again.
        lda     oldname
        ldx     oldname+1
        jsr     fm_name
        bcs     free

        ; The new path must be where the old one is
        lda     fm_slot
        cmp     newslot
        bne     elsewhere
        lda     fm_drive
        cmp     newdrive
        bne     elsewhere

        jsr     fm_isopen
        bcs     free
        jsr     fm_begin
        lda     oldname
        ldx     oldname+1
        jsr     fm_name
        bcs     free

        ; A file renamed to its own name is left as it is (POSIX); it
        ; exists, as fm_isopen found it
        ldx     #NAME_LEN-1
:       lda     fm_namebuf,x
        cmp     newbuf,x
        bne     :+
        dex
        bpl     :-
        lda     #$00            ; The same name: done
        beq     free            ; Branch always
:

        ; Refuse a new name that's in use: OPEN it without allocating
        lda     #<newbuf
        ldx     #>newbuf
        jsr     setname
        ldx     #$01            ; Don't allocate
        jsr     fm_open
        bcs     :+
        lda     #FMC_CLOSE      ; It exists
        jsr     fm_simple
        lda     #LIBERR_EXISTS  ; -> EEXIST
        bne     free            ; Branch always
:       cmp     #DOSERR_NOTFOUND
        bne     fmerr

        ; RENAME: old name at FM_NAME, new name at FM_NEWNAME
        lda     #<fm_namebuf
        ldx     #>fm_namebuf
        jsr     setname
        ldy     #FM_NEWNAME
        lda     #<newbuf
        sta     (fm_parmlist),y
        iny
        lda     #>newbuf
        sta     (fm_parmlist),y
        lda     #FMC_RENAME
        jsr     fm_simple
        bcs     fmerr           ; Locked, write protected, I/O error, ...
        bcc     free            ; Branch always (A = 0)
elsewhere:
        lda     #DOSERR_SYNTAX  ; -> EINVAL
        bne     free            ; Branch always
fmerr:  jsr     fm_maperr
free:   jsr     fm_freefcb      ; Preserves A
done:   ldx     #$00
        rts

;-----------------------------------------------------------------------------
; setname: Point the parameter list's FM_NAME at a name buffer.
;
; Input:        AX            byte*     the name buffer (NAME_LEN bytes, as
;                                       fm_name stores names)
;               fm_parmlist   byte*     the parameter list
; Output:       none
; Changes:      A and Y. X is unchanged.

setname:
        ldy     #FM_NAME
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y
        rts

        .bss

oldname:        .res    2       ; char*: the file's path
newname:        .res    2       ; char*: its new path
newbuf:         .res    NAME_LEN ; char[30]: the new name, as fm_name
                                ; stores it
newslot:        .res    1       ; byte: the new path's slot
newdrive:       .res    1       ; byte: the new path's drive
