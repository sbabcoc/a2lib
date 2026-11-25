;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; RDKEY, which stdio input reads keys with, for the VideoTerm library: on the
; card, it shows the card's cursor while waiting. For details, see section 3.4
; of DESIGN.
;

        .export         RDKEY

        .include        "apple2.inc"
        .include        "machine.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Read a key through the monitor's RDKEY ($FD0C) with ROM banked in, so the
; input hook (KSW) gets it. On the card, shows the card's cursor while
; waiting.
;
; Overrides:    cc65's RDKEY
; Output:       A             char      the key, with the high bit set
; Changes:      What RDKEY and the input hook change. On the card: X (vt_r10).
;               Ends with LC bank 2 read-only.

RDKEY:
        bit     vt_active
        bpl     :+
        lda     #R10_BLINK      ; Show the card's cursor while waiting
        jsr     vt_r10
:       ; Switch in ROM and call RDKEY
        bit     LC_ROM_RO
        jsr     MON_RDKEY       ; Display prompt and read key from user input routine

        ; Switch in LC bank 2 for R/O and return
        bit     LC_BANK2_RO
        bit     vt_active
        bpl     :+
        pha
        lda     #R10_HIDDEN
        jsr     vt_r10
        pla
:       rts
