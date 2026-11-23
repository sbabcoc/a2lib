;
; Scott Babcock, 2026-11-12
;
; seekend: move the file in fdtab slot Y to its end, for O_APPEND.
; Preserves Y. Returns carry clear, or carry set with an __oserror value
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
        jsr     fm_fdbegin

        ldy     #FCB::KIND
        lda     (ctlblock),y
        bmi     text
        ldy     #FCB::HDRLEN
        lda     (ctlblock),y
        bne     header
        lda     #LIBERR_NOEND   ; -> EINVAL
        sec
        bcs     out             ; Branch always

        ; POS = LEN; POSITION to HDRLEN + LEN
header: ldy     #FCB::LEN
        lda     (ctlblock),y
        ldy     #FCB::POS
        sta     (ctlblock),y
        ldy     #FCB::LEN+1
        lda     (ctlblock),y
        ldy     #FCB::POS+1
        sta     (ctlblock),y
        ldy     #FCB::HDRLEN
        lda     (ctlblock),y
        clc
        ldy     #FCB::LEN
        adc     (ctlblock),y
        pha
        ldy     #FCB::LEN+1
        lda     (ctlblock),y
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
:       cmp     #DOSERR_ENDDATA
        bne     fail

        ; Position on the terminator, so the next write replaces it
found:  ldy     #FCB::STATE
        lda     (ctlblock),y
        and     #<~FCBS_EOF
        sta     (ctlblock),y
        jsr     topos

check:  bcc     out
fail:   jsr     fm_maperr
        sec
out:    ldy     sslot
        rts

; topos: POSITION to the logical position POS (T files have no header).

topos:  ldy     #FCB::POS+1
        lda     (ctlblock),y
        tax
        dey
        lda     (ctlblock),y
        jmp     fm_position

        .bss

sslot:  .res    1
