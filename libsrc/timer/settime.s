;
; Scott Babcock, 2026-11-13
;
; clock_settime(), which sets the software clock that clock_gettime() reads,
; and a2_clock_age(), the seconds since then, or A2_CLOCK_UNSET if the clock
; was never set. For details, see section 6.3 of DESIGN.
;

        .export         _a2_clock_age, clk_offset
        .import         incsp1, return0

        .include        "time.inc"
        .include        "zeropage.inc"
        .include        "timer.inc"

; Shared storage
tp              = ptr1          ; struct timespec*: the caller's time

;-----------------------------------------------------------------------------
; Set the software clock. tv_nsec is ignored.
;
; Signature:    int __fastcall__ clock_settime (clockid_t clk_id, const struct
;               timespec* tp)
; Overrides:    cc65's clock_settime()
; Input:        C stack       clockid_t ignored
;               X:A           struct timespec*
;                                       the time
; Output:       clk_offset    long      tv_sec - t_sec
;               clk_setat     long      t_sec, now
;               clk_isset     byte      $80
;               X:A           int       0
; Changes:      Y; tp. Pops clk_id.

_clock_settime:

        ; Cleanup stack
        jsr     incsp1          ; Preserves A

        ; clk_offset = tv_sec - t_sec; remember when
        sta     tp
        stx     tp+1
        ldy     #$00            ; The loop test leaves C alone
        sec
:       lda     (tp),y
        sbc     t_sec,y
        sta     clk_offset,y
        lda     t_sec,y
        sta     clk_setat,y
        iny
        tya
        eor     #4
        bne     :-
        lda     #$80
        sta     clk_isset
        jmp     return0

;-----------------------------------------------------------------------------
; The seconds since clock_settime.
;
; Signature:    unsigned long a2_clock_age ()
; Input:        clk_isset     byte      bit 7: the clock was set
;               clk_setat     long      t_sec when it was
; Output:       sreg:X:A      long      t_sec - clk_setat, or A2_CLOCK_UNSET
;                                       ($FFFFFFFF) if the clock was never set
; Changes:      Flags. Y is unchanged.

_a2_clock_age:
        bit     clk_isset
        bmi     :+
        lda     #$FF            ; A2_CLOCK_UNSET
        sta     sreg
        sta     sreg+1
        tax
        rts
:       sec
        lda     t_sec
        sbc     clk_setat
        pha
        lda     t_sec+1
        sbc     clk_setat+1
        tax
        lda     t_sec+2
        sbc     clk_setat+2
        sta     sreg
        lda     t_sec+3
        sbc     clk_setat+3
        sta     sreg+1
        pla
        rts

        .data

clk_offset:     .dword  0       ; Clock time - t_sec
clk_setat:      .dword  0       ; t_sec when the clock was set
clk_isset:      .byte   0       ; Bit 7: set
