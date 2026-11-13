;
; IP65 timer driver using a2lib's cooperative timer (DESIGN.md 6.3)
;
; Replaces IP65's drivers/a2timer.s, which has no time base and makes each
; timer_read busy-wait about 33 ms. Here timer_read waits one tick (about
; 3.9 ms, running due timer callbacks) and returns the milliseconds
; counted since timer_init. Same interface:
;
;   timer_init:     reset the counter to 0
;   timer_read:     AX = milliseconds since timer_init (16 bits)
;   timer_seconds:  A = seconds of the minute, 00-59 in BCD, as IP65's
;                   time-of-day drivers return
;
; ld65 scans each library once, so this ships as an object file
; (lib/a2lib-ip65.o) to list on the link line, before IP65's library:
;   cl65 -t apple2 ... lib/a2lib-ip65.o ip65.lib ... lib/apple2-dos33.lib
;
; Callbacks run inside timer_read, so they must not call IP65.
;

        .export         timer_init, timer_read, timer_seconds
        .import         _a2_idle

        .include        "timer.inc"

        .code

timer_init:
        lda     t_ms
        sta     base
        lda     t_ms+1
        sta     base+1
        rts

timer_read:
        jsr     _a2_idle
        sec
        lda     t_ms
        sbc     base
        tay
        lda     t_ms+1
        sbc     base+1
        tax
        tya
        rts

timer_seconds:
        lda     t_sec60         ; Binary 0-59 to BCD
        ldx     #$FF
:       inx
        sec
        sbc     #10
        bcs     :-
        adc     #10             ; Units (C clear after the borrow)
        sta     units
        txa                     ; Tens
        asl
        asl
        asl
        asl
        ora     units
        rts

        .bss

base:   .res    2
units:  .res    1
