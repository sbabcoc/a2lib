;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; RDKEY, which stdio input reads keys with, for the Soft-70 library. On the
; VideoTerm, it shows the card's cursor while waiting. With Soft-70, it shows
; the blinking cursor at the model's, panning to it if following, and puts the
; monitor's own cursor on the hidden text screen, at row 0, column 0. The echo
; goes through COUT into the model. For details, see section 3.8 of DESIGN.
;

        .export         RDKEY
        .import         VTABZ, s70_curshow, s70_curhide

        .include        "apple2.inc"
        .include        "machine.inc"
        .include        "s80.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Read a key through the monitor's RDKEY ($FD0C) with ROM banked in, so the
; input hook (KSW) gets it, as stdio input does. On the VideoTerm, shows the
; card's cursor while waiting. With Soft-70, shows the blinking cursor at the
; model's, and puts the monitor's own cursor at row 0, column 0 of the hidden
; text screen. The echo goes through COUT into the model.
;
; Overrides:    cc65's RDKEY
; Output:       A             char      the key, with the high bit set
; Changes:      X, Y and flags; what RDKEY and the input hook change. With
;               Soft-70: CH, CV and BASL/BASH (VTABZ), and what s70_curshow
;               and s70_curhide change. Ends with LC bank 2 read-only.

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

;-----------------------------------------------------------------------------
; RDKEY with Soft-70.
;
; Output:       A             char      the key
; Changes:      As RDKEY.

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

;-----------------------------------------------------------------------------
; Call the monitor's RDKEY with ROM banked in, then LC bank 2 read-only again.
;
; Output:       A             char      the key
; Changes:      What RDKEY and the input hook change.

rom:    ; Switch in ROM and call RDKEY
        bit     LC_ROM_RO
        jsr     MON_RDKEY       ; Display prompt and read key from user input routine

        ; Switch in LC bank 2 for R/O and return
        bit     LC_BANK2_RO
        rts
