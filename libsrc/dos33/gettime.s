;
; Oliver Schmidt, 14.08.2018
;
; int __fastcall__ clock_gettime (clockid_t clk_id, struct timespec *tp);
;
; Software clock for DOS 3.3 (DESIGN.md 6.3): modified copy of
; libsrc/apple2/gettime.s from cc65. Under ProDOS, the stock code runs
; unchanged. Under DOS 3.3, which has no clock, the time is the software
; clock's offset (0 until clock_settime) plus the seconds counted by the
; cooperative timer, so before the clock is set it returns the up-time.
;

        .import         pushax, incsp1, incsp3, steaxspidx, return0
        .import         _mktime_dt
        .import         __dos_type, clk_offset

        .include        "time.inc"
        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "mli.inc"
        .include        "timer.inc"

_clock_gettime:
        ldy     __dos_type
        beq     dos33

        jsr     pushax

        ; Clear tv_nsec (+ tv_sec)
        sta     ptr1
        stx     ptr1+1
        lda     #$00
        ldy     #.sizeof(timespec)-1
:       sta     (ptr1),y
        dey
        bpl     :-

        ; Update date + time
        lda     #GET_TIME_CALL
        ldx     #GET_TIME_COUNT
        jsr     callmli
        bcs     oserr

        ; Convert DATELO/TIMELO to time_t
        lda     #<DATELO
        ldx     #>DATELO
        jsr     _mktime_dt

        ; Store
        ldy     #timespec::tv_sec
        jsr     steaxspidx

        ; Cleanup stack
        jsr     incsp1

        ; Return success
        jmp     return0

        ; Cleanup stack
oserr:  jsr     incsp3          ; Preserves A

        ; Set ___oserror
        jmp     ___mappederrno

; ------------------------------------------------------------------------
; DOS 3.3

dos33:  sta     ptr1
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
        bcc     :++
        clc
        ldy     #$00
:       lda     nsec,y
        adc     addend,y
        sta     nsec,y
        iny
        tya
        eor     #4              ; Leaves C alone
        bne     :-
:       asl     addend
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
