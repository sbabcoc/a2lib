;
; Scott Babcock, 2026-11-12
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

; Shared storage
offset_low      = ptr1          ; unsigned: the offset's low word
offset_high     = ptr2          ; unsigned: the offset's high word

        .code

;-----------------------------------------------------------------------------
; _lseek: Move an open file's position: off_t __fastcall__ lseek (int fd,
; off_t offset, int whence).
;
; Prepare:      open()
; Input:        C stack       int       fd: an open file, not the console
;               C stack       long      offset: from the position whence names
;               AX            int       whence: SEEK_CUR (0), SEEK_END (1) or
;                                       SEEK_SET (2)
; Output:       sreg:AX       long      the new position, or -1
;               errno         int       if -1: EBADF, EINVAL (the console, a
;                                       bad whence, a position below 0 or
;                                       above $FFFF), ESPIPE (past a header
;                                       file's length), or as __oserror maps
;               __oserror     byte      0, or the DOS 3.3 or library error
; Changes:      Y; offset_low, offset_high, fm_parmlist and ctlblock. Pops fd
;               and offset. SEEK_END on a T or raw file reads it from the
;               start to find the end. The file's end-of-data state is
;               cleared.

_lseek:
        ; Save whence
        sta     whence
        stx     whence+1

        ; Get and save offset
        jsr     popptr1         ; Low word: into offset_low (ptr1)
        jsr     popax
        sta     offset_high
        stx     offset_high+1

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
        jsr     fm_fdbegin

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
        lda     (ctlblock),y
        sta     base
        iny
        lda     (ctlblock),y
        sta     base+1
        jmp     add

        ; SEEK_END
end:    ldy     #FCB::HDRLEN
        lda     (ctlblock),y
        beq     scan
        ldy     #FCB::LEN       ; Header files: LEN
        lda     (ctlblock),y
        sta     base
        iny
        lda     (ctlblock),y
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
        lda     (ctlblock),y
        bmi     add
:       inc     base
        bne     sloop
        inc     base+1
        bne     sloop
        jmp     einval          ; Beyond 16 bits
send:   cmp     #DOSERR_ENDDATA
        jne     fmerr

        ; New position = base + offset; must be 0..$FFFF
add:    clc
        lda     base
        adc     offset_low
        sta     newpos
        lda     base+1
        adc     offset_low+1
        sta     newpos+1
        lda     #$00
        adc     offset_high
        bne     einval          ; Negative, or beyond 16 bits
        lda     #$00
        adc     offset_high+1
        bne     einval

        ; Header files: not past LEN; the File Manager offset is
        ; HDRLEN + newpos, which must also fit 16 bits
        ldy     #FCB::HDRLEN
        lda     (ctlblock),y
        beq     set
        ldy     #FCB::LEN
        lda     (ctlblock),y
        cmp     newpos
        iny
        lda     (ctlblock),y
        sbc     newpos+1
        bcs     :+
        lda     #LIBERR_POSITION ; -> ESPIPE
        jmp     oserr
:       ldy     #FCB::HDRLEN
        lda     (ctlblock),y
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
        sta     (ctlblock),y
        iny
        lda     newpos+1
        sta     (ctlblock),y
        ldy     #FCB::STATE
        lda     (ctlblock),y
        and     #<~FCBS_EOF
        sta     (ctlblock),y

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

whence: .res    2               ; int: SEEK_CUR, SEEK_END or SEEK_SET
base:   .res    2               ; unsigned: the position whence names
newpos: .res    2               ; unsigned: the new logical position
fmpos:  .res    2               ; unsigned: the File Manager's offset for it
