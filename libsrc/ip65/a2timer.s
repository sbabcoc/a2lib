;
; Scott Babcock, 2026-11-13
;
; An IP65 timer driver built on the cooperative timer. IP65's own Apple II
; driver has no time base, and makes each timer_read busy-wait about 33 ms.
; This one waits one tick, about 3.9 ms, running due timer callbacks, and
; returns the milliseconds since timer_init. Callbacks run inside timer_read,
; so they must not call IP65.
;
; ld65 scans each library once, so this ships as an object file, listed before
; IP65's library, with the timer library after it:
;
;   cl65 -t apple2 ... lib/a2lib-ip65.o ip65.lib ... \
;       lib/a2lib-timer.o lib/a2lib-timer.lib lib/a2lib-dos33.lib
;
; For details, see section 6.3 of DESIGN.
;

        .export         timer_init, timer_read, timer_seconds
        .import         _a2_idle

        .include        "timer.inc"

        .code

;-----------------------------------------------------------------------------
; Start IP65's millisecond counter from 0.
;
; Input:        t_ms          long      the timer's milliseconds since startup
; Output:       base          word      t_ms's low word
; Changes:      A. X and Y are unchanged.

timer_init:
        lda     t_ms
        sta     base
        lda     t_ms+1
        sta     base+1
        rts

;-----------------------------------------------------------------------------
; Wait one tick, then return the milliseconds since timer_init.
;
; Prepare:      timer_init
; Input:        base          word      t_ms's low word at timer_init
; Output:       X:A           word      the milliseconds since timer_init,
;                                       modulo 65536
; Changes:      Y; what a2_idle changes, including the callbacks of due
;               timers.

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

;-----------------------------------------------------------------------------
; The seconds of the current minute, as IP65's time-of-day drivers return
; them.
;
; Input:        t_sec60       byte      the seconds since startup, modulo 60
; Output:       A             byte      t_sec60 in BCD, $00-$59
; Changes:      X and flags; units. Y is unchanged.

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

base:   .res    2               ; word: t_ms's low word at timer_init
units:  .res    1               ; byte: timer_seconds' units digit
