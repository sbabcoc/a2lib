;
; Cooperative timer for the cc65 apple2 target (DESIGN.md 6.3)
;
; unsigned long a2_millis (void);
; void a2_idle (void);
; unsigned char a2_timer_start (unsigned ms, void (*fn) (void),
;                               unsigned char periodic);
; void __fastcall__ a2_timer_stop (unsigned char handle);
;
; Time advances only while the program waits in the library: the 15-cycle
; wait loops of cgetc, kbhit, a2_idle and the replacement KSW input routine
; below call a2_tick each time they increment RNDH. Linked only when a
; program uses the timer (or the software clock, or the 40-column window's
; position gauge); the constructor then installs a2_tick in the hook vector
; (tick.s) and the input routine in KSW.
;
; Callbacks run inside those wait loops, never during other library code.
; The dispatcher saves and restores the C runtime's zero page (cgetc keeps
; the character under its caret in tmp3, read.s its buffer in ptr1-ptr3)
; and the monitor's cursor (CH, CV, BASL, INVFLG), and doesn't dispatch
; again while a callback runs.
;
; Internal interface (for win.s, which must not disturb the C zero page
; while it runs inside cputc): a2_timer_arm takes the interval in ticks in
; tmr_ticks, the callback in tmr_fn and the periodic flag in tmr_per, and
; returns the handle in A ($FF if no slot is free); a2_timer_restart
; restarts the timer in slot X. Neither uses the zero page.
;
; Everything is in DATA: crt0 clears BSS after the constructors run
; (DESIGN.md 6.1).
;

        .export         _a2_millis, _a2_idle, _a2_timer_start, _a2_timer_stop
        .constructor    timerinit
        .destructor     timerdone
        .import         __dos_type, popax

        .include        "zeropage.inc"
        .include        "apple2.inc"
        .include        "timer.inc"

ZPLEN = 18                      ; sreg, regsave, ptr1-ptr4, tmp1-tmp4
        .assert tmp4 = sreg + ZPLEN - 1, lderror, "C zero page not contiguous"

        .segment        "ONCE"

timerinit:
        lda     #<a2_tick
        sta     a2_tickhook+1
        lda     #>a2_tick
        sta     a2_tickhook+2
        lda     #$80
        sta     a2_tickon

        ; Input through the replacement KSW routine. Keep the hooks to
        ; restore at exit.
        lda     KSWL
        sta     savek
        lda     KSWL+1
        sta     savek+1
        lda     DOS_KSW
        sta     savedos
        lda     DOS_KSW+1
        sta     savedos+1

        ; Under DOS 3.3 with DOS's keyboard intercept in KSW, become DOS's
        ; true input routine instead: on every character through its
        ; intercepts, DOS copies the true handlers into KSW and CSW and
        ; reinstalls its intercepts on the way out ("Beneath Apple DOS"
        ; ch. 8, $9ED1 and $A851), which would drop a routine stored in KSW
        ; directly. DOS restores the registers before calling the true
        ; routine, so it still gets A and Y as RDKEY passes them.
        lda     __dos_type
        bne     direct
        lda     KSWL
        cmp     DOS_KINT
        bne     direct
        lda     KSWL+1
        cmp     DOS_KINT+1
        bne     direct
        lda     #<keyin
        sta     DOS_KSW
        lda     #>keyin
        sta     DOS_KSW+1
        lda     #$80
        sta     viados
        rts

direct: lda     #<keyin
        sta     KSWL
        lda     #>keyin
        sta     KSWL+1
        rts

        .code

timerdone:
        bit     viados          ; Installed as DOS's true input routine?
        bpl     :+
        lda     savedos
        sta     DOS_KSW
        lda     savedos+1
        sta     DOS_KSW+1
        rts

:       lda     savek
        sta     KSWL
        lda     savek+1
        sta     KSWL+1

        ; DOS's reconnect routine may have moved our hook into its saved
        ; true input hook; put that back too
        lda     __dos_type
        bne     :+
        lda     DOS_KSW
        cmp     #<keyin
        bne     :+
        lda     DOS_KSW+1
        cmp     #>keyin
        bne     :+
        lda     savedos
        sta     DOS_KSW
        lda     savedos+1
        sta     DOS_KSW+1
:       rts

; ------------------------------------------------------------------------
; a2_tick: one tick. Called with LC bank 2 enabled for reading (cc65's
; normal state). Changes A, X and Y; the zero page only when dispatching,
; and then restores it.

a2_tick:
        ; Milliseconds this tick: TICK_MS, plus 1 when the error term
        ; reaches TICK_DEN (Bresenham)
        ldx     #TICK_MS
        lda     t_err
        cmp     #TICK_DEN - TICK_NUM
        bcc     :+
        sbc     #TICK_DEN - TICK_NUM    ; C set
        inx
        bne     :++                     ; Branch always
:       adc     #TICK_NUM               ; C clear
:       sta     t_err

        ; t_ms += X
        txa
        clc
        adc     t_ms
        sta     t_ms
        bcc     :+
        inc     t_ms+1
        bne     :+
        inc     t_ms+2
        bne     :+
        inc     t_ms+3

        ; t_rem += X; carry whole seconds into t_sec and t_sec60
:       txa
        clc
        adc     t_rem
        sta     t_rem
        bcc     :+
        inc     t_rem+1
:       lda     t_rem+1
        cmp     #>1000
        bcc     slots
        lda     t_rem
        cmp     #<1000
        bcc     slots
        sbc     #<1000          ; At most 1003, so the high byte becomes 0
        sta     t_rem
        lda     #$00
        sta     t_rem+1
        inc     t_sec
        bne     :+
        inc     t_sec+1
        bne     :+
        inc     t_sec+2
        bne     :+
        inc     t_sec+3
:       ldx     t_sec60
        inx
        cpx     #60
        bcc     :+
        ldx     #$00
:       stx     t_sec60

        ; Count down the active timers
slots:  lda     nact
        beq     check
        ldx     #NSLOT-1
sl:     lda     s_flag,x
        and     #TF_ACTIVE
        beq     next
        lda     s_remlo,x
        bne     :+
        dec     s_remhi,x
:       dec     s_remlo,x
        bne     next
        lda     s_remhi,x
        bne     next

        ; Expired: due; periodic ones restart, one-shots stop counting
        lda     s_flag,x
        ora     #TF_DUE
        sta     s_flag,x
        and     #TF_PERIODIC
        beq     :+
        lda     s_ivlo,x
        sta     s_remlo,x
        lda     s_ivhi,x
        sta     s_remhi,x
        jmp     :++
:       lda     s_flag,x
        and     #<~TF_ACTIVE
        sta     s_flag,x
        dec     nact
:       lda     #$01
        sta     anydue
next:   dex
        bpl     sl

check:  lda     anydue
        beq     done
        bit     busy
        bpl     dispatch
done:   rts

; ------------------------------------------------------------------------
; dispatch: run the callbacks of the due timers.

dispatch:
        lda     #$80
        sta     busy
        ldx     #ZPLEN-1
:       lda     sreg,x
        sta     zpsave,x
        dex
        bpl     :-
        lda     CH
        sta     savech
        lda     CV
        sta     savecv
        lda     BASL
        sta     savebas
        lda     BASH
        sta     savebas+1
        lda     INVFLG
        sta     saveinv

        lda     #$00
        sta     anydue
        ldx     #$00
dl:     lda     s_flag,x
        and     #TF_DUE
        beq     dn
        lda     s_flag,x
        and     #TF_PERIODIC
        bne     :+
        lda     #$00            ; One-shot: free the slot
        beq     :++             ; Branch always
:       lda     s_flag,x
        and     #<~TF_DUE
:       sta     s_flag,x
        lda     s_fnlo,x
        sta     dvec+1
        lda     s_fnhi,x
        sta     dvec+2
        stx     dslot
        jsr     dvec
        ldx     dslot
dn:     inx
        cpx     #NSLOT
        bne     dl

        lda     saveinv
        sta     INVFLG
        lda     savebas+1
        sta     BASH
        lda     savebas
        sta     BASL
        lda     savecv
        sta     CV
        lda     savech
        sta     CH
        ldx     #ZPLEN-1
:       lda     zpsave,x
        sta     sreg,x
        dex
        bpl     :-
        lda     #$00
        sta     busy
        rts

; ------------------------------------------------------------------------
; C interface

_a2_millis:
        lda     t_ms+3
        sta     sreg+1
        lda     t_ms+2
        sta     sreg
        ldx     t_ms+1
        lda     t_ms
        rts

; One tick, with the same 15-cycle loop as cgetc's (the BIT keeps the
; timing); keys are left alone.

_a2_idle:
:       inc     RNDL
        bne     :+
        inc     RNDH
        jmp     a2_tick
:       bit     KBD
        jmp     :--

_a2_timer_start:
        sta     tmr_per
        jsr     popax           ; fn
        sta     tmr_fn
        stx     tmr_fn+1
        jsr     popax           ; ms
        sta     ms
        stx     ms+1

        ; prod = ms * TICK_DEN (24 bits)
        lda     #$00
        sta     prod
        sta     prod+1
        sta     prod+2
        lda     #TICK_DEN
        sta     mult
        ldx     #8
ml:     asl     prod
        rol     prod+1
        rol     prod+2
        asl     mult
        bcc     :+
        clc
        lda     prod
        adc     ms
        sta     prod
        lda     prod+1
        adc     ms+1
        sta     prod+1
        bcc     :+
        inc     prod+2
:       dex
        bne     ml

        ; Round: prod += TICK_MSDEN / 2
        clc
        lda     prod
        adc     #<(TICK_MSDEN / 2)
        sta     prod
        lda     prod+1
        adc     #>(TICK_MSDEN / 2)
        sta     prod+1
        bcc     :+
        inc     prod+2

        ; ticks = prod / TICK_MSDEN (quotient replaces prod)
:       lda     #$00
        sta     rem
        sta     rem+1
        ldx     #24
dv:     asl     prod
        rol     prod+1
        rol     prod+2
        rol     rem
        rol     rem+1
        lda     rem
        sec
        sbc     #<TICK_MSDEN
        tay
        lda     rem+1
        sbc     #>TICK_MSDEN
        bcc     :+
        sta     rem+1
        sty     rem
        inc     prod
:       dex
        bne     dv

        ; At least one tick
        lda     prod
        sta     tmr_ticks
        lda     prod+1
        sta     tmr_ticks+1
        ora     tmr_ticks
        bne     a2_timer_arm
        inc     tmr_ticks
        ; Fall through

a2_timer_arm:
        ldx     #$00
:       lda     s_flag,x
        beq     found
        inx
        cpx     #NSLOT
        bne     :-
        lda     #$FF            ; No free slot
        ldx     #$00
        rts
found:  lda     tmr_ticks
        sta     s_ivlo,x
        sta     s_remlo,x
        lda     tmr_ticks+1
        sta     s_ivhi,x
        sta     s_remhi,x
        lda     tmr_fn
        sta     s_fnlo,x
        lda     tmr_fn+1
        sta     s_fnhi,x
        lda     tmr_per
        beq     :+
        lda     #TF_PERIODIC
:       ora     #TF_ALLOC | TF_ACTIVE
        sta     s_flag,x
        inc     nact
        txa
        ldx     #$00
        rts

a2_timer_restart:
        lda     s_ivlo,x
        sta     s_remlo,x
        lda     s_ivhi,x
        sta     s_remhi,x
        lda     s_flag,x
        and     #TF_ACTIVE
        bne     :+
        inc     nact
:       lda     s_flag,x
        ora     #TF_ACTIVE
        and     #<~TF_DUE
        sta     s_flag,x
        rts

_a2_timer_stop:
        cmp     #NSLOT
        bcs     :++
        tax
        lda     s_flag,x
        and     #TF_ACTIVE
        beq     :+
        dec     nact
:       lda     #$00
        sta     s_flag,x
:       rts

; ------------------------------------------------------------------------
; keyin: the KSW input routine, mirroring the Autostart ROM's KEYIN
; ($FD1B): entered from RDKEY with A = the character under the cursor and
; Y = CH; restores that character when a key arrives and returns the key
; in A, with X and Y unchanged. Runs with ROM enabled, so it is in LOWCODE.

        .segment        "LOWCODE"

keyin:
:       inc     RNDL
        bne     :+
        inc     RNDH
        jsr     kswtick
:       bit     KBD
        bpl     :--
        sta     (BASL),y
        lda     KBD
        bit     KBDSTRB
        rts

; kswtick: a2_tick in cc65's banking (LC bank 2 for reading, so callbacks
; run as the program does), then ROM again. Preserves A, X and Y.

kswtick:
        pha
        txa
        pha
        tya
        pha
        bit     $C080           ; LC bank 2, read only
        jsr     a2_tick
        bit     $C082           ; ROM
        pla
        tay
        pla
        tax
        pla
        rts

; ------------------------------------------------------------------------

        .data

t_ms:           .dword  0       ; Milliseconds since startup
t_err:          .byte   0       ; Bresenham error term, 0 .. TICK_DEN-1
t_rem:          .word   0       ; Milliseconds into the current second
t_sec:          .dword  0       ; Seconds since startup
t_sec60:        .byte   0       ; t_sec modulo 60

nact:           .byte   0       ; Active (counting) timers
anydue:         .byte   0
busy:           .byte   0       ; Bit 7: callbacks running

s_flag:         .res    NSLOT, 0
s_remlo:        .res    NSLOT, 0
s_remhi:        .res    NSLOT, 0
s_ivlo:         .res    NSLOT, 0
s_ivhi:         .res    NSLOT, 0
s_fnlo:         .res    NSLOT, 0
s_fnhi:         .res    NSLOT, 0

tmr_ticks:      .word   0       ; a2_timer_arm's arguments
tmr_fn:         .word   0
tmr_per:        .byte   0

dvec:           jmp     $0000   ; Callback, stored by dispatch (an indirect
                                ; JMP could hit the NMOS JMP ($xxFF) bug)
dslot:          .byte   0
zpsave:         .res    ZPLEN, 0
savech:         .byte   0
savecv:         .byte   0
savebas:        .word   0
saveinv:        .byte   0

savek:          .word   0       ; KSW and DOS's saved KSW at startup
savedos:        .word   0
viados:         .byte   0       ; Bit 7: installed as DOS's true input routine

ms:             .word   0       ; a2_timer_start's arithmetic
prod:           .res    3, 0
mult:           .byte   0
rem:            .word   0
