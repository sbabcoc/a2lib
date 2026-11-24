;
; Scott Babcock, 2026-11-13
;
; int __fastcall__ clock_gettime (clockid_t clk_id, struct timespec *tp);
;
; Software clock for DOS 3.3 (DESIGN.md 6.3). Replaces
; libsrc/apple2/gettime.s from cc65, which reads the ProDOS clock. DOS 3.3
; has no clock: the time is the software clock's offset (0 until
; clock_settime) plus the seconds counted by the cooperative timer, so
; before the clock is set it returns the up-time.
;

        .import         incsp1, return0
        .import         clk_offset

        .include        "time.inc"
        .include        "zeropage.inc"
        .include        "timer.inc"

; Shared storage
tp              = ptr1          ; struct timespec*: the caller's time

;-----------------------------------------------------------------------------
; _clock_gettime: Read the software clock: int __fastcall__ clock_gettime
; (clockid_t clk_id, struct timespec* tp). Before clock_settime, the time is
; the up-time.
;
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
