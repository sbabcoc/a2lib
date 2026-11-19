;
; Oliver Schmidt, 18.04.2005
;
; DOS 3.3 support for the cc65 apple2 target: modified copy of
; libsrc/apple2/initcwd.s from cc65 (DESIGN.md 5.5). The only change:
; under DOS 3.3, __cwd is "/S/D", DOS's last-used slot and drive, which
; are the current directory (fmname.s, syschdir.s). The ProDOS code is
; unchanged.
;

        .export         initcwd
        .import         __cwd, __dos_type

        .include        "zeropage.inc"
        .include        "apple2.inc"
        .include        "mli.inc"
        .include        "fm.inc"        ; a2lib: DOS_SLOT, DOS_DRIVE

initcwd:
        ; Check for ProDOS 8
        lda     __dos_type
        beq     dos33

        ; Save random counter
        lda     RNDL
        pha
        lda     RNDH
        pha

        ; Call MLI
        ; We're not using mli.s' callmli because its
        ; mliparam is in BSS and this will be called
        ; before LC code is moved to the Language Card.

        jsr     $BF00           ; MLI call entry point
        .byte   GET_PREFIX_CALL ; MLI command
        .addr   mli_parameters  ; MLI parameter

        ; Restore random counter
        pla
        sta     RNDH
        pla
        sta     RNDL

        ; Check for null prefix
        ldx     __cwd
        beq     done

        ; Remove length byte and trailing slash
        dex
        stx     tmp1
        ldx     #$00
:       lda     __cwd + 1,x
        sta     __cwd,x
        inx
        cpx     tmp1
        bcc     :-

        ; Add terminating zero
        lda     #$00
        sta     __cwd,x

done:   rts

        ; a2lib: DOS 3.3's current directory, "/S/D"
dos33:  lda     #'/'
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

        .rodata

mli_parameters:
        .byte $01               ; Number of parameters
        .addr __cwd             ; Address of parameter
