;
; Scott Babcock, 2026-11-12
;
; Path names. DOS 3.3 has a slot and drive for every file, and no
; subdirectories, so a path names at most a slot, a drive and a file:
;
;   "/6/2/NAME"         slot 6, drive 2
;   "2/NAME"            drive 2 in the current slot
;   "NAME", "./NAME"    the current slot and drive
;
; The current directory is DOS's last-used slot and drive; a path's own slot
; and drive don't change it. The volume is always 0, any volume, as for a DOS
; command without ",V".
;
; A name starts with a letter, so a leading digit is a drive, never part of a
; name. It has at most NAME_LEN characters, any but "/", and is stored in
; uppercase with the high bit set, padded with spaces, as DOS's command parser
; stores names. For details, see section 5.5 of DESIGN.
;

        .include        "zeropage.inc"
        .include        "fm.inc"

; Shared storage
path            = ptr1          ; char*: the path being parsed

        .code

;-----------------------------------------------------------------------------
; Parse a directory path, for opendir() and chdir(): "", ".", "D" or "/S/D",
; each optionally ending in "/". Sets no parameter list fields, so it needs no
; fm_begin.
;
; Input:        X:A           char*     the path
; Output:       C             flag      clear: parsed; set: not a directory
;                                       path
;               A             byte      if C set: DOSERR_SYNTAX (EINVAL)
;               fm_slot       byte      the slot (1-7): the path's, or DOS's
;                                       current one
;               fm_drive      byte      the drive (1-2): the path's, or DOS's
;                                       current one
;               fm_volume     byte      0 (any volume)
; Changes:      Y and path; X is unchanged. If C is set, fm_slot and fm_drive
;               may be changed.

fm_location:
        jsr     location
        bcs     bad
        lda     (path),y        ; Nothing may follow
        bne     bad
        clc
        rts

;-----------------------------------------------------------------------------
; Parse a file's path into the parameter list's name, volume, drive and slot
; fields.
;
; Prepare:      fm_begin
; Input:        X:A           char*     the path: "/S/D/NAME", "D/NAME",
;                                       "NAME" or "./NAME"
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      clear: parsed; set: not a file's path
;               A             byte      if C set: DOSERR_SYNTAX (EINVAL)
;               fm_namebuf    char[30]  if C clear: the name, uppercase, with
;                                       the high bit set and padded with
;                                       HI_SPACE
;               fm_slot       byte      the slot (1-7), as fm_location
;               fm_drive      byte      the drive (1-2), as fm_location
;               fm_volume     byte      0 (any volume)
;               fm_parmlist   byte*     if C clear: FM_NAME = fm_namebuf;
;                                       FM_VOLUME, FM_DRIVE and FM_SLOT from
;                                       the above
; Changes:      X, Y and path. If C is set, fm_namebuf, fm_slot and fm_drive
;               may be changed.

fm_name:
        jsr     location
        bcs     bad

        ; Blank the name buffer
        ldx     #NAME_LEN-1
        lda     #HI_SPACE
:       sta     fm_namebuf,x
        dex
        bpl     :-

        ; The name must start with a letter
        lda     (path),y
        jsr     upcase
        cmp     #'A'
        bcc     bad
        cmp     #'Z'+1
        bcs     bad

        ; Copy it to the end of the string; no "/" in it
        ldx     #$00
@copy:  lda     (path),y
        beq     store
        cmp     #'/'
        beq     bad
        cpx     #NAME_LEN
        bcs     bad             ; Too long
        jsr     upcase
        ora     #$80
        sta     fm_namebuf,x
        inx
        iny
        bne     @copy           ; Branch always: Y < 256 for a valid path

bad:    lda     #DOSERR_SYNTAX  ; -> EINVAL
        sec
        rts

        ; Set the parameter list fields
store:  ldy     #FM_NAME
        lda     #<fm_namebuf
        sta     (fm_parmlist),y
        iny
        lda     #>fm_namebuf
        sta     (fm_parmlist),y

        .assert FM_DRIVE = FM_VOLUME + 1, error
        .assert FM_SLOT = FM_DRIVE + 1, error
        ldy     #FM_VOLUME
        lda     fm_volume
        sta     (fm_parmlist),y
        iny
        lda     fm_drive
        sta     (fm_parmlist),y
        iny
        lda     fm_slot
        sta     (fm_parmlist),y
        clc
        rts

;-----------------------------------------------------------------------------
; Parse the location at the start of a path: "/S/D", "D" or ".", each followed
; by the end or "/" (skipped). A path that starts with none of these has no
; location, and is all name.
;
; Input:        X:A           char*     the path
; Output:       C             flag      clear: parsed; set: a syntax error
;               Y             byte      if C clear: the offset of what follows
;                                       the location (the name, or the end)
;               path          char*     the path
;               fm_slot       byte      the path's slot, or DOS_SLOT
;               fm_drive      byte      the path's drive, or DOS_DRIVE
;               fm_volume     byte      0
; Changes:      A. X is unchanged.

location:
        sta     path
        stx     path+1
        lda     #$00
        sta     fm_volume
        lda     DOS_DRIVE
        sta     fm_drive
        lda     DOS_SLOT
        sta     fm_slot

        ldy     #$00
        lda     (path),y
        cmp     #'/'
        beq     @absolute
        cmp     #'.'
        beq     @dot

        ; "D" or "D/": a drive digit, then the end or "/"
        jsr     drive
        bcs     @plain
        iny
        jmp     endpart
@plain: ldy     #$00            ; Not a drive: a name
        clc
        rts

        ; "." or "./"
@dot:   iny
        jmp     endpart

        ; "/S/D" or "/S/D/"
@absolute:
        iny
        lda     (path),y
        sec
        sbc     #'1'
        cmp     #NSLOTS         ; Slots 1-7
        bcs     @bad
        adc     #1
        sta     fm_slot
        iny
        lda     (path),y
        cmp     #'/'
        bne     @bad
        iny
        jsr     drive
        bcs     @bad
        iny
        jmp     endpart
@bad:   sec
        rts

;-----------------------------------------------------------------------------
; End a location component: the end of the path, or "/", which is skipped.
;
; Input:        Y             byte      the offset after the component
;               path          char*     the path
; Output:       C             flag      clear: valid; set: something else
;                                       follows
;               Y             byte      if C clear: the offset of what follows
;                                       (past a "/")
; Changes:      A. X is unchanged.

endpart:
        lda     (path),y
        beq     @done
        cmp     #'/'
        bne     @bad
        iny
@done:  clc
        rts
@bad:   sec
        rts

;-----------------------------------------------------------------------------
; Parse a drive digit ('1' or '2') that the end of the path or "/" follows.
;
; Input:        Y             byte      the digit's offset
;               path          char*     the path
; Output:       C             flag      clear: a drive; set: not one
;               fm_drive      byte      if C clear: the drive (1-2); else
;                                       unchanged
;               Y             byte      unchanged
; Changes:      A. X is unchanged.

drive:  lda     (path),y
        sec
        sbc     #'1'
        cmp     #NDRIVES        ; Drives 1-2
        bcs     @no
        pha
        iny
        lda     (path),y        ; What follows the digit
        beq     @yes            ; End of the string
        cmp     #'/'
        beq     @yes
        dey
        pla
        sec
@no:    rts
@yes:   dey
        pla
        clc
        adc     #1              ; 1 or 2
        sta     fm_drive
        rts                     ; C clear

;-----------------------------------------------------------------------------
; Convert a lowercase ASCII letter to uppercase.
;
; Input:        A             char      the character, high bit clear
; Output:       A             char      uppercase if it was a lowercase
;                                       letter, else unchanged
; Changes:      C, N and Z. X and Y are unchanged.

upcase: cmp     #'a'
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:       rts

        .bss

fm_namebuf:     .res    NAME_LEN ; char[30]: the last name parsed, as DOS
                                ; stores names
fm_volume:      .res    1       ; byte: the last path's volume (always 0)
fm_drive:       .res    1       ; byte: the last path's drive (1-2)
fm_slot:        .res    1       ; byte: the last path's slot (1-7)
