;
; Scott Babcock, 2026-11-12
;
; DOS 3.3 path names for the cc65 apple2 target (DESIGN.md 5.5)
;
; DOS 3.3 has a slot and drive for every file, and no subdirectories, so a
; path names at most a slot, a drive and a file, as POSIX paths do:
;
;   "/6/2/NAME"         slot 6, drive 2
;   "2/NAME"            drive 2 in the current slot
;   "NAME", "./NAME"    the current slot and drive
;
; The current directory is DOS's last-used slot and drive ($AA6A, $AA68):
; chdir() sets them (syschdir.s), and getcwd() gives "/6/2" (initcwd.s).
; A path's own slot and drive don't change it. The volume is always 0, any
; volume, as for a DOS command without ",V".
;
; A name starts with a letter (so a leading digit is a drive, never part
; of a name), has at most NAME_LEN characters, and may hold any character
; but "/". It is converted to uppercase and stored with the high bit set,
; padded with HI_SPACE, as DOS's command parser stores names.
;
; fm_name:     parse the path in AX into the File Manager parameter list
;              (ptr3, from fm_begin): the name buffer and its address, and
;              the volume, drive and slot fields.
; fm_location: parse a directory, for opendir() and chdir(): "", ".",
;              "2", "/6/2", each optionally ending in "/". Sets fm_slot,
;              fm_drive and fm_volume but no parameter list fields, so it
;              doesn't need fm_begin.
;
; Both return carry clear, or carry set with A = DOSERR_SYNTAX (EINVAL).
; Uses ptr1.
;

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

fm_location:
        jsr     location
        bcs     bad
        lda     (ptr1),y        ; Nothing may follow
        bne     bad
        clc
        rts

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
        lda     (ptr1),y
        jsr     upcase
        cmp     #'A'
        bcc     bad
        cmp     #'Z'+1
        bcs     bad

        ; Copy it to the end of the string; no "/" in it
        ldx     #$00
@copy:  lda     (ptr1),y
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
        sta     (ptr3),y
        iny
        lda     #>fm_namebuf
        sta     (ptr3),y

        .assert FM_DRIVE = FM_VOLUME + 1, error
        .assert FM_SLOT = FM_DRIVE + 1, error
        ldy     #FM_VOLUME
        lda     fm_volume
        sta     (ptr3),y
        iny
        lda     fm_drive
        sta     (ptr3),y
        iny
        lda     fm_slot
        sta     (ptr3),y
        clc
        rts

; ------------------------------------------------------------------------
; location: parse the slot and drive at the start of the path in AX into
; fm_slot and fm_drive (the current ones if the path doesn't give them),
; with fm_volume 0. Returns carry clear with Y indexing what follows (the
; name, or the end), or carry set on a syntax error.
;
;   "/S/D"  "/S/D/..."  "D"  "D/..."  "."  "./..."  anything else: Y = 0

location:
        sta     ptr1
        stx     ptr1+1
        lda     #$00
        sta     fm_volume
        lda     DOS_DRIVE
        sta     fm_drive
        lda     DOS_SLOT
        sta     fm_slot

        ldy     #$00
        lda     (ptr1),y
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
        lda     (ptr1),y
        sec
        sbc     #'1'
        cmp     #NSLOTS         ; Slots 1-7
        bcs     @bad
        adc     #1
        sta     fm_slot
        iny
        lda     (ptr1),y
        cmp     #'/'
        bne     @bad
        iny
        jsr     drive
        bcs     @bad
        iny
        jmp     endpart
@bad:   sec
        rts

; endpart: after a location component, the end of the string, or "/"
; followed by more (skipped). Returns as location.

endpart:
        lda     (ptr1),y
        beq     @done
        cmp     #'/'
        bne     @bad
        iny
@done:  clc
        rts
@bad:   sec
        rts

; drive: the drive digit at (ptr1),y ('1' or '2'), followed by the end of
; the string or "/", into fm_drive. Carry set (and fm_drive unchanged) if
; it isn't one.

drive:  lda     (ptr1),y
        sec
        sbc     #'1'
        cmp     #NDRIVES        ; Drives 1-2
        bcs     @no
        pha
        iny
        lda     (ptr1),y        ; What follows the digit
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

; ------------------------------------------------------------------------

upcase: cmp     #'a'
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:       rts

        .bss

fm_namebuf:     .res    NAME_LEN
fm_volume:      .res    1       ; Volume, slot and drive of the last path parsed
fm_drive:       .res    1
fm_slot:        .res    1
