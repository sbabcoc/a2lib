;
; Ullrich von Bassewitz, 17.05.2000
; Scott Babcock, 2026-11-19
;
; The errno value for each __oserror value: DOS 3.3's own error numbers, as
; ONERR reports them, and the library's codes from $10 for conditions DOS 3.3
; has no number for. The search is cc65's; only the table differs. For
; details, see section 5.6 of DESIGN.
;

        .export         ___osmaperrno

        .include        "errno.inc"
        .include        "fm.inc"

;-----------------------------------------------------------------------------
; Map an __oserror value to an errno value, for cc65's ___mappederrno.
;
; Overrides:    cc65's ___osmaperrno
; Input:        A             byte      oserror: a DOS 3.3 error number or a
;                                       library code
; Output:       AX            int       the errno value, or EUNKNOWN for a
;                                       code not in the table
; Changes:      Flags. Y is unchanged.

___osmaperrno:
        ldx     #ErrTabSize
:       cmp     ErrTab-2,x      ; Search for the error code
        beq     :+              ; Jump if found
        dex
        dex
        bne     :-              ; Next entry

        ; Code not found, return EUNKNOWN
        lda     #<EUNKNOWN
        ldx     #>EUNKNOWN
        rts

        ; Found the code
:       lda     ErrTab-1,x
        ldx     #>$0000
        rts

        .rodata

ErrTab: .byte   DOSERR_LANG,      ENOSYS        ; Language not available
        .byte   DOSERR_RANGE,     EINVAL        ; Range error (call type)
        .byte   DOSERR_SUBRANGE,  EINVAL        ; Range error (sub-call type)
        .byte   DOSERR_WPROT,     EACCES        ; Write protected
;       .byte   DOSERR_ENDDATA,   EUNKNOWN      ; End of data (handled by read)
        .byte   DOSERR_NOTFOUND,  ENOENT        ; File not found
        .byte   DOSERR_VOLUME,    ENOENT        ; Volume mismatch
        .byte   DOSERR_IO,        EIO           ; I/O error
        .byte   DOSERR_FULL,      ENOSPC        ; Disk full
        .byte   DOSERR_LOCKED,    EACCES        ; File locked
        .byte   DOSERR_SYNTAX,    EINVAL        ; Syntax error
        .byte   DOSERR_NOBUFS,    ENOMEM        ; No buffers available
        .byte   DOSERR_TYPE,      ENOEXEC       ; File type mismatch
        .byte   DOSERR_TOOLARGE,  ENOMEM        ; Program too large
        .byte   DOSERR_NOTDIRECT, EINVAL        ; Not direct command
        .byte   LIBERR_EXISTS,    EEXIST        ; File exists
        .byte   LIBERR_OPEN,      EINVAL        ; File is open
        .byte   LIBERR_NOTDOS,    ENODEV        ; Not a DOS 3.3 disk
        .byte   LIBERR_POSITION,  ESPIPE        ; Position out of range
        .byte   LIBERR_NOEND,     EINVAL        ; No recorded end

ErrTabSize = (* - ErrTab)
