;
; initcwd: set __cwd to "/S/D", DOS 3.3's last-used slot and drive, which
; are the current directory (fmname.s, syschdir.s; DESIGN.md 5.5).
; Replaces libsrc/apple2/initcwd.s from cc65, which asks ProDOS for its
; prefix.
;

        .export         initcwd
        .import         __cwd

        .include        "fm.inc"        ; DOS_SLOT, DOS_DRIVE

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
