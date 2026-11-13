;
; RDKEY routine
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/rdkey.s (Oliver Schmidt). On the VideoTerm, shows its
; cursor while waiting. In the window, pans to the cursor (if following)
; and points the monitor's cursor (CH, CV, BASL) at it, so RDKEY's own
; cursor appears in the right place; the echo goes through COUT into the
; window.
;

        .export         RDKEY
        .import         VTABZ

        .include        "apple2.inc"
        .include        "win.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

RDKEY:
        bit     vt_active
        bpl     win
        lda     #R10_BLINK      ; Show the card's cursor while waiting
        jsr     vt_r10
        jsr     rom
        pha
        lda     #R10_HIDDEN
        jsr     vt_r10
        pla
        rts

win:    jsr     win_show
        jsr     win_cursorcol
        bcc     :+
        lda     #$00            ; Not visible (not following): column 0
:       sta     CH
        lda     win_y
        sta     CV
        jsr     VTABZ           ; BASL for CV

rom:    ; Switch in ROM and call RDKEY
        bit     $C082
        jsr     $FD0C           ; Display prompt and read key from user input routine

        ; Switch in LC bank 2 for R/O and return
        bit     $C080
        rts
