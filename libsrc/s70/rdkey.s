;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; RDKEY routine
;
; Soft-70 backend (a2lib-soft70.lib), based on cc65's
; libsrc/apple2/rdkey.s (Oliver Schmidt). On the VideoTerm, shows its
; cursor while waiting. With Soft-70, shows the blinking cursor at the
; model's cursor (panning to it if following) while the monitor's RDKEY
; reads through the input hook, as stdio input does; the monitor's own
; cursor goes to the hidden text screen, at row 0, column 0. The echo goes
; through COUT into the model.
;

        .export         RDKEY
        .import         VTABZ, s70_curshow, s70_curhide

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

RDKEY:
        bit     vt_active
        bpl     s70
        lda     #R10_BLINK      ; Show the card's cursor while waiting
        jsr     vt_r10
        jsr     rom
        pha
        lda     #R10_HIDDEN
        jsr     vt_r10
        pla
        rts

s70:    jsr     s70_curshow
        lda     #$00
        sta     CH
        sta     CV
        jsr     VTABZ           ; BASL for CV
        jsr     rom
        pha
        jsr     s70_curhide
        pla
        rts

rom:    ; Switch in ROM and call RDKEY
        bit     $C082
        jsr     $FD0C           ; Display prompt and read key from user input routine

        ; Switch in LC bank 2 for R/O and return
        bit     $C080
        rts
