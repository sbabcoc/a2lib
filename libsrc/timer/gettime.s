;
; Scott Babcock, 2026-11-13
;
; clock_gettime() from the software clock. DOS 3.3 has no clock: the time is
; the offset clock_settime() sets, 0 until then, plus the seconds the
; cooperative timer has counted, so before the clock is set it gives the
; up-time. For details, see section 6.3 of DESIGN.
;

        .import         incsp1, return0
        .import         clk_offset

        .include        "time.inc"
        .include        "zeropage.inc"
        .include        "timer.inc"

; Shared storage
tp              = ptr1          ; struct timespec*: the caller's time

;-----------------------------------------------------------------------------
; Read the software clock. Before clock_settime, the time is the up-time.
;
; Signature:    int __fastcall__ clock_gettime (clockid_t clk_id, struct
;               timespec* tp)
; Overrides:    cc65's clock_gettime()
; Input:        C stack       clockid_t clk_id: ignored
;               AX            struct timespec*
;                                       tp: where to store the time
; Output:       *tp           struct timespec
;                                       tv_sec: t_sec + clk_offset; tv_nsec:
;                                       t_rem * 1000000
;               AX            int       0
; Changes:      Y; tp, mul, addend and nsec. Pops clk_id.

_clock_gettime:
        sta     tp
        stx     tp+1
        jsr     incsp1          ; Drop clk_id

        ; tv_sec = t_sec + clk_offset (the loop test leaves C alone)
        .assert timespec::tv_sec = 0, error
        ldy     #$00
        clc
:       lda     t_sec,y
        adc     clk_offset,y
        sta     (tp),y
        iny
        tya
        eor     #4
        bne     :-

        ; tv_nsec = t_rem * 1000000: shift-and-add over t_rem's 10 bits
        lda     t_rem
        sta     mul
        lda     t_rem+1
        sta     mul+1
        lda     #<1000000
        sta     addend
        lda     #>1000000
        sta     addend+1
        lda     #^1000000
        sta     addend+2
        lda     #$00
        sta     addend+3
        ldx     #3
:       sta     nsec,x
        dex
        bpl     :-
        ldx     #10
mloop:  lsr     mul+1
        ror     mul
        bcc     noadd
        clc
        ldy     #$00
:       lda     nsec,y
        adc     addend,y
        sta     nsec,y
        iny
        tya
        eor     #4              ; Leaves C alone
        bne     :-
noadd:  asl     addend
        rol     addend+1
        rol     addend+2
        rol     addend+3
        dex
        bne     mloop

        ldy     #timespec::tv_nsec
        ldx     #$00
:       lda     nsec,x
        sta     (tp),y
        iny
        inx
        cpx     #4
        bne     :-
        jmp     return0

        .bss

mul:    .res    2               ; word: t_rem, shifted out bit by bit
addend: .res    4               ; long: 1000000, doubled each bit
nsec:   .res    4               ; long: the product, tv_nsec
