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

_clock_gettime:
        sta     ptr1
        stx     ptr1+1
        jsr     incsp1          ; Drop clk_id

        ; tv_sec = t_sec + clk_offset (the loop test leaves C alone)
        .assert timespec::tv_sec = 0, error
        ldy     #$00
        clc
:       lda     t_sec,y
        adc     clk_offset,y
        sta     (ptr1),y
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
        sta     (ptr1),y
        iny
        inx
        cpx     #4
        bne     :-
        jmp     return0

        .bss

mul:    .res    2
addend: .res    4
nsec:   .res    4
