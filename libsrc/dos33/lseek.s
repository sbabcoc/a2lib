;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; off_t __fastcall__ lseek (int fd, off_t offset, int whence);
;
; Replaces libsrc/apple2/lseek.s from cc65 (same interface: whence 0 =
; SEEK_CUR, 1 = SEEK_END, 2 = SEEK_SET; result in sreg:X:A, or -1).
; See DESIGN.md 5.7.
;
;   Header files (A, I, B): the end is the length in the header. Seeking
;     past it fails with ESPIPE, as SET_MARK past EOF does under ProDOS.
;   T files: the end is the first $00 on disk, found by scanning from the
;     start. Any position may be set, including past the end, so that
;     records of random-access files can be reached (DESIGN.md 5.2).
;   Raw files: the end is the end of the data, as for reads.
;   All: positions are limited to 16 bits (the File Manager's POSITION
;     takes a 16-bit whole-file offset); larger ones fail with EINVAL, as
;     positions beyond ProDOS's 24-bit range do.
;

        .export         _lseek
        .import         popax, popptr1

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

        .code

_lseek:
        ; Save whence
        sta     whence
        stx     whence+1

        ; Get and save offset: low word in ptr1, high word in ptr2
        jsr     popptr1
        jsr     popax
        sta     ptr2
        stx     ptr2+1

        ; Get and process fd
        jsr     popax
        jsr     getfd           ; Returns A, Y and C
        jcs     errno

        ; Check for device
        cmp     #$80
        jcs     einval

        ; Valid whence values are 0..2
        ldx     whence+1
        jne     einval
        ldx     whence
        cpx     #3
        jcs     einval

        ; Control block and parameter list
        lda     fdtab + FD::BUFFER,y
        sta     ptr4
        lda     fdtab + FD::BUFFER+1,y
        sta     ptr4+1
        jsr     fm_begin

        ; Base position for whence
        lda     #$00
        sta     base
        sta     base+1
        ldx     whence
        cpx     #2              ; SEEK_SET: 0
        beq     add
        cpx     #1
        beq     end
        ldy     #FCB::POS       ; SEEK_CUR: POS
        lda     (ptr4),y
        sta     base
        iny
        lda     (ptr4),y
        sta     base+1
        jmp     add

        ; SEEK_END
end:    ldy     #FCB::HDRLEN
        lda     (ptr4),y
        beq     scan
        ldy     #FCB::LEN       ; Header files: LEN
        lda     (ptr4),y
        sta     base
        iny
        lda     (ptr4),y
        sta     base+1
        jmp     add

        ; T and raw files: count bytes from the start to the end
scan:   lda     #$00
        tax
        jsr     fm_position
        jcs     fmerr
sloop:  jsr     fm_readbyte
        bcs     send
        ldy     #FCB::KIND      ; T files end at the first $00
        tax
        bne     :+
        lda     (ptr4),y
        bmi     add
:       inc     base
        bne     sloop
        inc     base+1
        bne     sloop
        jmp     einval          ; Beyond 16 bits
send:   cmp     #FMR_ENDDATA
        jne     fmerr

        ; New position = base + offset; must be 0..$FFFF
add:    clc
        lda     base
        adc     ptr1
        sta     newpos
        lda     base+1
        adc     ptr1+1
        sta     newpos+1
        lda     #$00
        adc     ptr2
        bne     einval          ; Negative, or beyond 16 bits
        lda     #$00
        adc     ptr2+1
        bne     einval

        ; Header files: not past LEN; the File Manager offset is
        ; HDRLEN + newpos, which must also fit 16 bits
        ldy     #FCB::HDRLEN
        lda     (ptr4),y
        beq     set
        ldy     #FCB::LEN
        lda     (ptr4),y
        cmp     newpos
        iny
        lda     (ptr4),y
        sbc     newpos+1
        bcs     :+
        lda     #$4D            ; ProDOS "Position out of range" -> ESPIPE
        jmp     oserr
:       ldy     #FCB::HDRLEN
        lda     (ptr4),y
        clc
        adc     newpos
        sta     fmpos
        lda     newpos+1
        adc     #$00
        sta     fmpos+1
        bcs     einval
        bcc     pos             ; Branch always

set:    lda     newpos
        sta     fmpos
        lda     newpos+1
        sta     fmpos+1

        ; POSITION, then update POS and clear the end-of-data state
pos:    lda     fmpos
        ldx     fmpos+1
        jsr     fm_position
        bcs     fmerr
        ldy     #FCB::POS
        lda     newpos
        sta     (ptr4),y
        iny
        lda     newpos+1
        sta     (ptr4),y
        ldy     #FCB::STATE
        lda     (ptr4),y
        and     #<~FCBS_EOF
        sta     (ptr4),y

        ; Return the position in sreg:X:A
        lda     #$00
        sta     sreg
        sta     sreg+1
        sta     ___oserror
        ldx     newpos+1
        lda     newpos
        rts

        ; Load errno code
einval: lda     #EINVAL

        ; Set __errno
errno:  jsr     ___directerrno  ; Leaves -1 in AX
        stx     sreg            ; Extend return value to 32 bits
        stx     sreg+1
        rts

        ; Set ___oserror
fmerr:  jsr     fm_maperr
oserr:  jsr     ___mappederrno  ; Leaves -1 in AX
        stx     sreg            ; Extend return value to 32 bits
        stx     sreg+1
        rts

        .bss

whence: .res    2
base:   .res    2
newpos: .res    2
fmpos:  .res    2
