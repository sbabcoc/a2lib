;
; Oliver Schmidt, 15.08.2018
;
; int __fastcall__ clock_settime (clockid_t clk_id, const struct timespec *tp);
; unsigned long a2_clock_age (void);
;
; Software clock for DOS 3.3 (DESIGN.md 6.3): modified copy of
; libsrc/apple2/settime.s from cc65. Under ProDOS, the stock code runs
; unchanged. Under DOS 3.3, clock_settime sets the software clock read by
; clock_gettime (tv_nsec is ignored); a2_clock_age returns the seconds
; since then, or A2_CLOCK_UNSET ($FFFFFFFF) if the clock was never set.
;

        .export         _a2_clock_age, clk_offset
        .import         __dos_type
        .import         incsp1, return0

        .include        "time.inc"
        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "mli.inc"
        .include        "timer.inc"

_clock_settime:

        ; Cleanup stack
        jsr     incsp1          ; Preserves A

        ; Check for ProDOS 8
        ldy     __dos_type
        beq     dos33

        ; Check for realtme clock
        tay                     ; Save A
        lda     MACHID
        lsr     a
        bcs     erange
        tya                     ; Restore A

        ; Get tm
        .assert timespec::tv_sec = 0, error
        jsr     _localtime
        sta     ptr1
        stx     ptr1+1

        ; Set date
        ldy     #tm::tm_mon
        lda     (ptr1),y
        clc
        adc     #$01            ; Move [0..11] to [1..12]
        asl
        asl
        asl
        asl
        asl
        php                     ; Save month msb
        ldy     #tm::tm_mday
        ora     (ptr1),y
        sta     DATELO
        ldy     #tm::tm_year
        lda     (ptr1),y
        cmp     #100            ; Year since 1900 < 100?
        bcc     :+              ; Yes, leave alone
        sbc     #100            ; Move 20xx to 19xx
:       plp                     ; Restore month msb
        rol
        sta     DATELO+1

        ; Return success
        jmp     return0

        ; Load errno code
erange: lda     #ERANGE

        ; Set __errno
        jmp     ___directerrno

; ------------------------------------------------------------------------
; DOS 3.3: clk_offset = tv_sec - t_sec; remember when

dos33:  sta     ptr1
        stx     ptr1+1
        ldy     #$00            ; The loop test leaves C alone
        sec
:       lda     (ptr1),y
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
