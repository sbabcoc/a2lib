;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; seekend: move the file in fdtab slot Y to its end, for O_APPEND.
; Preserves Y. Returns carry clear, or carry set with a ProDOS error code
; in A (for ___mappederrno).
;
;   Header files: the end is the length recorded in the header.
;   T files:      the end is the first $00 on disk, found by scanning
;                 forward from the current position (after the first
;                 append the scan stops at once).
;   Raw files:    no end is recorded below sector granularity, so
;                 O_APPEND fails with EINVAL rather than append after
;                 padding (DESIGN.md 1, guiding principle).
;

        .export         seekend

        .include        "zeropage.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

        .code

seekend:
        sty     sslot
        lda     fdtab + FD::BUFFER,y
        sta     ptr4
        lda     fdtab + FD::BUFFER+1,y
        sta     ptr4+1
        jsr     fm_begin

        ldy     #FCB::KIND
        lda     (ptr4),y
        bmi     text
        ldy     #FCB::HDRLEN
        lda     (ptr4),y
        bne     header
        lda     #$04            ; ProDOS "Bad parameter count" -> EINVAL
        sec
        bcs     out             ; Branch always

        ; POS = LEN; POSITION to HDRLEN + LEN
header: ldy     #FCB::LEN
        lda     (ptr4),y
        ldy     #FCB::POS
        sta     (ptr4),y
        ldy     #FCB::LEN+1
        lda     (ptr4),y
        ldy     #FCB::POS+1
        sta     (ptr4),y
        ldy     #FCB::HDRLEN
        lda     (ptr4),y
        clc
        ldy     #FCB::LEN
        adc     (ptr4),y
        pha
        ldy     #FCB::LEN+1
        lda     (ptr4),y
        adc     #$00
        tax
        pla
        jsr     fm_position
        jmp     check

        ; Scan from POS to the first $00 (or the end of the data)
text:   jsr     topos
        bcs     fail
:       jsr     fm_readbyte
        bcs     :+
        tax
        beq     found
        jsr     fm_incpos
        jmp     :-
:       cmp     #FMR_ENDDATA
        bne     fail

        ; Position on the terminator, so the next write replaces it
found:  ldy     #FCB::STATE
        lda     (ptr4),y
        and     #<~FCBS_EOF
        sta     (ptr4),y
        jsr     topos

check:  bcc     out
fail:   jsr     fm_maperr
        sec
out:    ldy     sslot
        rts

; topos: POSITION to the logical position POS (T files have no header).

topos:  ldy     #FCB::POS+1
        lda     (ptr4),y
        tax
        dey
        lda     (ptr4),y
        jmp     fm_position

        .bss

sslot:  .res    1
