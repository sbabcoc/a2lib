;
; Scott Babcock, 2026-11-19
;
; The current directory, which getcwd() reports: DOS's last-used slot and
; drive. For details, see section 5.5 of DESIGN.
;

        .export         initcwd
        .import         __cwd

        .include        "fm.inc"        ; DOS_SLOT, DOS_DRIVE

        .code

;-----------------------------------------------------------------------------
; Set __cwd, which getcwd() copies, to "/S/D" from DOS's last-used slot and
; drive: at startup, called by the constructor of cc65's getcwd() support,
; and after chdir().
;
; Overrides:    cc65's initcwd
; Input:        DOS_SLOT      byte      the slot (1-7)
;               DOS_DRIVE     byte      the drive (1-2)
; Output:       __cwd         char[]    "/S/D"
; Changes:      A. X and Y are unchanged.

initcwd:
        lda     #'/'
        sta     __cwd
        sta     __cwd+2
        lda     DOS_SLOT
        ora     #'0'
        sta     __cwd+1
        lda     DOS_DRIVE
        ora     #'0'
        sta     __cwd+3
        lda     #$00
        sta     __cwd+4
        rts
