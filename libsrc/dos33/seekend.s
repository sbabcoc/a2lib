;
; Scott Babcock, 2026-11-12
;
; The end of a file, for O_APPEND:
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

;-----------------------------------------------------------------------------
; seekend: Move an open file to its end, before a write with O_APPEND.
;
; Prepare:      open()
; Input:        Y             byte      the fdtab slot's offset, of an open
;                                       file
; Output:       C             flag      clear: at the end; set: an error
;               A             byte      if C set: the __oserror value:
;                                       LIBERR_NOEND (EINVAL) for a raw file,
;                                       which has no recorded end, or a DOS
;                                       3.3 error
;               Y             byte      unchanged
;               ctlblock      FCB*      the slot's control block, POS at the
;                                       end
; Changes:      X; fm_parmlist. A T file is read from its position to its
;               first $00, and its end-of-data state cleared.

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

;-----------------------------------------------------------------------------
; topos: POSITION a T file, which has no header, to its logical position.
;
; Prepare:      fm_begin
; Input:        ctlblock      FCB*      the control block
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      X and Y.

topos:  ldy     #FCB::POS+1
        lda     (ctlblock),y
        tax
        dey
        lda     (ctlblock),y
        jmp     fm_position

        .bss

sslot:  .res    1               ; byte: the fdtab slot's offset
