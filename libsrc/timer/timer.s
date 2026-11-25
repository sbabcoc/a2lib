;
; Scott Babcock, 2026-11-13
;
; The cooperative timer: milliseconds since startup, a wait of one tick, and
; timers whose callbacks run when they expire. Linked only when a program uses
; it, the software clock, or Soft-70's position gauge and cursor.
;
; Time advances only while the program waits in the library: the 15-cycle wait
; loops of cgetc(), kbhit(), a2_idle() and the input routine here, which takes
; the place of the monitor's, tick it each time they increment RNDH. Callbacks
; run inside those loops, never during other library code. The C runtime's
; zero page and the monitor's cursor are saved around them, and no callback
; starts while another runs.
;
; Soft-70 starts and restarts timers through an interface that leaves the zero
; page alone, since it runs inside cputc(). Everything the constructor sets is
; in DATA, as the startup code clears BSS after the constructors run. For
; details, see section 6.3 of DESIGN.
;

        .export         _a2_millis, _a2_idle, _a2_timer_start, _a2_timer_stop
        .constructor    timerinit
        .destructor     timerdone
        .import         popax

        .include        "zeropage.inc"
        .include        "apple2.inc"
        .include        "timer.inc"
        .include        "machine.inc"

ZPLEN = 18                      ; sreg, regsave, ptr1-ptr4, tmp1-tmp4
        .assert tmp4 = sreg + ZPLEN - 1, lderror, "C zero page not contiguous"

        .segment        "ONCE"

;-----------------------------------------------------------------------------
; The module constructor: point a2_tickhook at a2_tick, set a2_tickon, and
; install keyin as the input routine: as DOS's true input routine when DOS's
; intercept is in KSW, else in KSW itself.
;
; Input:        KSWL          word      the input hook
;               DOS_KSW       word      DOS's saved true input hook
; Output:       a2_tickhook   JMP       to a2_tick
;               a2_tickon     byte      $80
;               savek         word      KSW, as at entry
;               savedos       word      DOS_KSW, as at entry
;               viados        byte      $80 if keyin became DOS's true input
;                                       routine
; Changes:      A; KSWL or DOS_KSW.

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

;-----------------------------------------------------------------------------
; The module destructor: put back the input hooks timerinit replaced,
; including a DOS_KSW that DOS's reconnect routine copied keyin into.
;
; Input:        viados        byte      bit 7: keyin is DOS's true input
;                                       routine
;               savek         word      KSW, as at entry
;               savedos       word      DOS_KSW, as at entry
; Changes:      A and flags; KSWL and DOS_KSW.

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

;-----------------------------------------------------------------------------
; One tick: advance the clocks, count down the active timers, and run the due
; timers' callbacks unless a callback is already running. Called through
; a2_tickhook from the wait loops, with LC bank 2 enabled for reading.
;
; Input:        t_err         byte      the Bresenham error term
;               s_flag        byte[4]   each slot's TF_* flags
; Output:       t_ms          long      milliseconds since startup
;               t_rem         word      milliseconds into the current second
;               t_sec         long      seconds since startup
;               t_sec60       byte      t_sec modulo 60
; Changes:      A, X and Y; the slots' counts and flags, nact and anydue. CH,
;               CV, BASL, BASH and INVFLG, and the C zero page from sreg to
;               tmp4, are saved before callbacks and restored after
;               (dispatch).

a2_tick:
        ; Milliseconds this tick: TICK_MS, plus 1 when the error term
        ; reaches TICK_DEN (Bresenham)
        ldx     #TICK_MS
        lda     t_err
        cmp     #TICK_DEN - TICK_NUM
        bcc     @nocarry
        sbc     #TICK_DEN - TICK_NUM    ; C set
        inx
        bne     @err                    ; Branch always
@nocarry:
        adc     #TICK_NUM               ; C clear
@err:   sta     t_err

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
        beq     @oneshot
        lda     s_ivlo,x
        sta     s_remlo,x
        lda     s_ivhi,x
        sta     s_remhi,x
        jmp     @due
@oneshot:
        lda     s_flag,x
        and     #<~TF_ACTIVE
        sta     s_flag,x
        dec     nact
@due:   lda     #$01
        sta     anydue
next:   dex
        bpl     sl

check:  lda     anydue
        beq     done
        bit     busy
        bpl     dispatch
done:   rts

;-----------------------------------------------------------------------------
; Run the callbacks of the due timers, freeing each due one-shot's slot.
;
; Input:        s_flag        byte[4]   TF_DUE marks a due timer
;               s_fnlo        byte[4]   each slot's callback, low byte (high
;                                       byte in s_fnhi)
; Output:       anydue        byte      0
; Changes:      A, X and Y; s_flag, dvec and dslot; what the callbacks change.
;               CH, CV, BASL, BASH and INVFLG, and the C zero page from sreg
;               to tmp4, are saved before callbacks and restored after. busy
;               is $80 while they run.

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
        bne     @periodic
        lda     #$00            ; One-shot: free the slot
        beq     @flag           ; Branch always
@periodic:
        lda     s_flag,x
        and     #<~TF_DUE
@flag:  sta     s_flag,x
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

;-----------------------------------------------------------------------------
; The milliseconds since startup.
;
; Signature:    unsigned long a2_millis ()
; Input:        t_ms          long      milliseconds since startup
; Output:       sreg:X:A      long      t_ms
; Changes:      Flags. Y is unchanged.

_a2_millis:
        lda     t_ms+3
        sta     sreg+1
        lda     t_ms+2
        sta     sreg
        ldx     t_ms+1
        lda     t_ms
        rts

;-----------------------------------------------------------------------------
; Wait one tick, with the same 15-cycle loop as cgetc, leaving keys alone.
;
; Signature:    void a2_idle ()
; Changes:      A, X and Y; RNDL and RNDH; what a2_tick changes.
; Note:         The BIT KBD, whose result is unused, keeps the loop at cgetc's
;               timing.

_a2_idle:
@wait:  inc     RNDL
        bne     @key
        inc     RNDH
        jmp     a2_tick
@key:   bit     KBD
        jmp     @wait

;-----------------------------------------------------------------------------
; Start a timer. Converts ms to ticks, rounded and at least one, and falls
; into a2_timer_arm.
;
; Signature:    unsigned char __fastcall__ a2_timer_start (unsigned ms, void
;               (*fn) (), unsigned char periodic)
; Input:        C stack       unsigned  interval in milliseconds
;               C stack       void (*)()
;                                       callback
;               A             unsigned char
;                                       nonzero to restart it each time it
;                                       expires
; Output:       X:A           unsigned char
;                                       the handle (the slot), or
;                                       A2_TIMER_NONE ($FF) if no slot is free
; Changes:      Y; tmr_ticks, tmr_fn, tmr_per, ms, prod, mult and rem. Pops ms
;               and fn.

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

;-----------------------------------------------------------------------------
; Start a timer, for Soft-70's model, which must leave the C zero page alone:
; find a free slot and fill it.
;
; Input:        tmr_ticks     word      the interval in ticks, at least 1
;               tmr_fn        void (*)()
;                                       the callback
;               tmr_per       byte      nonzero: periodic
; Output:       A             byte      the handle (the slot), or $FF if no
;                                       slot is free
;               X             byte      0
; Changes:      Flags; the slot and nact. Leaves the zero page alone.

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

;-----------------------------------------------------------------------------
; Restart a timer from its full interval, for Soft-70's model.
;
; Prepare:      a2_timer_arm
; Input:        X             byte      the handle (the slot)
; Changes:      A and flags; the slot, and nact if it wasn't counting. X and Y
;               are unchanged.

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

;-----------------------------------------------------------------------------
; Stop a timer and free its slot. A handle that isn't a slot, such as
; A2_TIMER_NONE, is ignored.
;
; Signature:    void __fastcall__ a2_timer_stop (unsigned char handle)
; Prepare:      a2_timer_start()
; Input:        A             unsigned char
;                                       timer handle
; Changes:      A, X and flags; the slot, and nact if it was counting.

_a2_timer_stop:
        cmp     #NSLOT
        bcs     @done
        tax
        lda     s_flag,x
        and     #TF_ACTIVE
        beq     @free
        dec     nact
@free:  lda     #$00
        sta     s_flag,x
@done:  rts

; ------------------------------------------------------------------------

        .segment        "LOWCODE"       ; keyin runs with ROM enabled

;-----------------------------------------------------------------------------
; The input routine, as the Autostart ROM's KEYIN ($FD1B) but ticking while it
; waits. Entered from RDKEY, or from DOS's intercept, with ROM enabled.
;
; Input:        A             char      the character under the cursor
;               Y             byte      CH
;               BASL          byte*     the cursor's line
; Output:       A             char      the key, with the high bit set
; Changes:      Flags; RNDL and RNDH; the cursor's character, put back;
;               KBDSTRB, cleared; what a2_tick changes, but X and Y are
;               unchanged (kswtick).

keyin:
@wait:  inc     RNDL
        bne     @key
        inc     RNDH
        jsr     kswtick
@key:   bit     KBD
        bpl     @wait
        sta     (BASL),y
        lda     KBD
        bit     KBDSTRB
        rts

;-----------------------------------------------------------------------------
; Run a2_tick from keyin with cc65's banking, LC bank 2 for reading, so
; callbacks run as the program does; then ROM again.
;
; Changes:      What a2_tick changes, but A, X and Y are unchanged.

kswtick:
        pha
        txa
        pha
        tya
        pha
        bit     LC_BANK2_RO
        jsr     a2_tick
        bit     LC_ROM_RO
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

tmr_ticks:      .word   0       ; a2_timer_arm's arguments: ticks,
tmr_fn:         .word   0       ; the callback,
tmr_per:        .byte   0       ; and nonzero for periodic

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
