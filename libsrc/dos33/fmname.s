;
; DOS 3.3 file name handling for the cc65 apple2 target
;
; fm_name: parse the C string in AX into the File Manager parameter list
; (ptr3, set by fm_begin): the 30-byte name buffer and name address, and
; the volume, drive and slot fields. See DESIGN.md, section 5.5.
;
;   "NAME"              Last-used slot and drive, any volume
;   "NAME,S6,D2,V254"   Any combination and order of suffixes
;
; The name must start with a letter, has at most 30 characters and is
; converted to uppercase (ProDOS treats names case-insensitively too).
; It is stored with the high bit set and padded with $A0, the way DOS's
; own command parser fills its name buffer. As with DOS commands, an
; explicit S or D becomes the new default.
;
; Returns carry clear on success, or carry set with A = $40 (ProDOS
; "Invalid pathname", which maps to EINVAL). Uses ptr1, tmp1-tmp4.
;

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

fm_name:
        sta     ptr1
        stx     ptr1+1

        ; Defaults: any volume, last-used drive and slot
        lda     #$00
        sta     volume
        sta     given
        lda     DOS_DRIVE
        sta     drive
        lda     DOS_SLOT
        sta     slot

        ; Blank the name buffer
        ldx     #30-1
        lda     #$A0
:       sta     fm_namebuf,x
        dex
        bpl     :-

        ; The name must start with a letter
        ldy     #$00
        lda     (ptr1),y
        jsr     upcase
        cmp     #'A'
        bcc     bad
        cmp     #'Z'+1
        bcs     bad

        ; Copy the name up to the end or the first comma
        ldx     #$00
copy:   lda     (ptr1),y
        beq     store
        cmp     #','
        beq     suffix
        cpx     #30
        bcs     bad             ; Too long
        jsr     upcase
        ora     #$80
        sta     fm_namebuf,x
        inx
        iny
        bne     copy
        beq     bad             ; Branch always: string too long

        ; ",<letter><number>"
suffix: iny                     ; Skip the comma
        lda     (ptr1),y
        jsr     upcase
        sta     tmp2            ; Keyword letter
        iny
        jsr     getnum          ; Value in tmp3
        bcs     bad
        lda     tmp2
        cmp     #'S'
        beq     is_s
        cmp     #'D'
        beq     is_d
        cmp     #'V'
        bne     bad

        ; V: 0 (any) to 254
        lda     tmp3
        cmp     #255
        bcs     bad
        sta     volume
        bcc     next            ; Branch always

        ; S: 1 to 7
is_s:   lda     tmp3
        beq     bad
        cmp     #8
        bcs     bad
        sta     slot
        lda     given
        ora     #GIVEN_S
        bne     setgiven        ; Branch always

        ; D: 1 or 2
is_d:   lda     tmp3
        beq     bad
        cmp     #3
        bcs     bad
        sta     drive
        lda     given
        ora     #GIVEN_D
setgiven:
        sta     given

next:   lda     (ptr1),y
        beq     store
        cmp     #','
        beq     suffix
        ; Anything else is invalid

bad:    lda     #$40            ; ProDOS "Invalid pathname"
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
        lda     volume
        sta     (ptr3),y
        iny
        lda     drive
        sta     (ptr3),y
        iny
        lda     slot
        sta     (ptr3),y

        ; Explicit S and D become DOS's defaults
        lda     given
        and     #GIVEN_S
        beq     :+
        lda     slot
        sta     DOS_SLOT
        lda     #$00
        sta     DOS_SLOT+1
:       lda     given
        and     #GIVEN_D
        beq     :+
        lda     drive
        sta     DOS_DRIVE
        lda     #$00
        sta     DOS_DRIVE+1
:       clc
        rts

; ------------------------------------------------------------------------
; getnum: parse 1 to 3 decimal digits at (ptr1),y into tmp3 (at most 255).
; Advances Y. Returns carry set if there are no digits or on overflow.

getnum: lda     #$00
        sta     tmp3
        ldx     #$00            ; Digit count
digit:  lda     (ptr1),y
        sec
        sbc     #'0'
        cmp     #10
        bcs     endnum
        sta     tmp1
        lda     tmp3            ; tmp3 = tmp3 * 10 + digit
        asl
        bcs     ovf
        sta     tmp4            ; * 2
        asl
        bcs     ovf
        asl
        bcs     ovf             ; * 8
        adc     tmp4
        bcs     ovf             ; * 10
        adc     tmp1
        bcs     ovf
        sta     tmp3
        inx
        iny
        bne     digit
endnum: txa
        beq     ovf             ; No digits
        clc
        rts
ovf:    sec
        rts

; ------------------------------------------------------------------------

upcase: cmp     #'a'
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:       rts

GIVEN_S = $01
GIVEN_D = $02

        .bss

fm_namebuf:     .res    30
volume:         .res    1
drive:          .res    1
slot:           .res    1
given:          .res    1
