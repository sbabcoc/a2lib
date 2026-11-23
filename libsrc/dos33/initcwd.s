;
; Scott Babcock, 2026-11-19
;
; DOS 3.3 current directory for the cc65 apple2 target (DESIGN.md 5.5)
;
; Replaces libsrc/apple2/initcwd.s from cc65, which asks ProDOS for its
; prefix. The current directory is DOS 3.3's last-used slot and drive
; (fmname.s, syschdir.s).
;

        .export         initcwd
        .import         __cwd

        .include        "fm.inc"        ; DOS_SLOT, DOS_DRIVE

        .code

;-----------------------------------------------------------------------------
; initcwd: Set __cwd, which getcwd() copies, to "/S/D" from DOS's last-used
; slot and drive: at startup, called by the constructor of cc65's _cwd.s, and
; after chdir().
;
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
