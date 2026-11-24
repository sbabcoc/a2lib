;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; RDKEY routine
;
;
; VideoTerm backend (a2lib-vt.lib): modified copy of libsrc/apple2/rdkey.s
; from cc65; if the card is in use, shows its cursor while waiting for the
; key (DESIGN.md 3.4).

        .export         RDKEY

        .include        "apple2.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; RDKEY: Read a key through the monitor's RDKEY ($FD0C) with ROM banked in, so
; the input hook (KSW) gets it. On the card, shows the card's cursor while
; waiting.
;
; Input:        none
; Output:       A             char      the key, with the high bit set
; Changes:      What RDKEY and the input hook change. On the card: X (vt_r10).
;               Ends with LC bank 2 read-only.

RDKEY:
        bit     vt_active
        bpl     :+
        lda     #R10_BLINK      ; Show the card's cursor while waiting
        jsr     vt_r10
:       ; Switch in ROM and call RDKEY
        bit     $C082
        jsr     $FD0C           ; Display prompt and read key from user input routine

        ; Switch in LC bank 2 for R/O and return
        bit     $C080
        bit     vt_active
        bpl     :+
        pha
        lda     #R10_HIDDEN
        jsr     vt_r10
        pla
:       rts
