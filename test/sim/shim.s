; sim65 harness support: stubs for Apple II-only imports, a C entry to
; a2_tick, and cycle measurement through sim65's counter peripheral.
        .export         _tick, _cyc_empty, _cyc_tick
        .export         __dos_type, callmli, _mktime_dt
        .import         a2_tick
        .constructor    nokey
LATCH   := $FFC0
VALUE   := $FFC2
        .data
__dos_type:     .byte   0       ; DOS 3.3
        .segment        "ONCE"
nokey:  lda     #$00            ; $C000 (KBD) is plain RAM here: no key
        sta     $C000
        rts
        .code
callmli:
_mktime_dt:
        rts
_tick:  jmp     a2_tick
; Cycles from latch to latch, without and with a JSR a2_tick between
_cyc_empty:
        sta     LATCH
        lda     VALUE
        sta     t0
        lda     VALUE+1
        sta     t0+1
        sta     LATCH
        jmp     diff
_cyc_tick:
        sta     LATCH
        lda     VALUE
        sta     t0
        lda     VALUE+1
        sta     t0+1
        jsr     a2_tick
        sta     LATCH
diff:   sec
        lda     VALUE
        sbc     t0
        pha
        lda     VALUE+1
        sbc     t0+1
        tax
        pla
        rts
        .bss
t0:     .res    2
