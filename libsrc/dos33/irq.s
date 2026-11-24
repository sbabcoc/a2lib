;
; Scott Babcock, 2026-11-12
;
; IRQ handling under DOS 3.3
;
; Replaces libsrc/apple2/irq.s from cc65, which allocates a ProDOS
; interrupt vector table entry. DOS 3.3 has no such table, so initirq
; installs the handlers itself. See DESIGN.md section 6.
;
; A 16K Language Card on a II+ has no switch that reports whether its RAM
; or the ROM is enabled for reading, so a handler can't save and restore
; that state. As ProDOS does, initirq tells the state from the
; way the interrupt arrives:
;
;   LC RAM enabled: the CPU takes the vector at $FFFE from LC RAM, where
;     crt0 put irq_6502 for DOS 3.3 programs. initirq replaces it with
;     lcirq, which calls the interruptors without touching the banking.
;     This relies on a2lib's crt0.s, which patches that vector before the
;     constructors run; stock crt0 patches it afterward, overwriting lcirq.
;   ROM enabled (during COUT, RDKEY, File Manager and RWTS calls, or on a
;     machine without a Language Card): the CPU takes ROM's vector, to the
;     Autostart ROM's IRQ handler ($FA40), which saves A in $45, passes a
;     BRK to the monitor, and jumps through $3FE. initirq points $3FE at
;     romirq, which restores A from $45 before RTI.
;
; Either way the interrupted code resumes with the banking it had. An
; interrupt no interruptor handles, and a BRK in LC RAM, go where they
; went before initirq: to the previous $3FE handler, and to crt0's
; irq_6502 (which, as in stock cc65, leaves ROM enabled).
;
; DOS 3.3's RWTS masks interrupts while it runs ("Beneath Apple DOS"
; ch. 2, ch. 8 at $B7B5), so disk I/O is safe with interrupts enabled.
;

        .export         initirq, doneirq
        .import         callirq

        .include        "apple2.inc"
        .include        "machine.inc"

IRQLOC  := $03FE                ; Monitor's maskable-interrupt vector
SAVEA   := $45                  ; Where the ROM IRQ handler saves A

        .segment        "ONCE"

;-----------------------------------------------------------------------------
; initirq: Install romirq at $3FE and lcirq at LC RAM's $FFFE, keeping the old
; vectors. Called by the constructor of cc65's runtime/callirq.s, in programs
; with an interruptor.
;
; Input:        IRQLOC        word      the previous $3FE handler
;               ROM_IRQ       word      LC RAM's vector: crt0's irq_6502
; Output:       romnext       JMP       to the previous $3FE handler
;               lcnext        JMP       to the previous LC RAM vector
;               installed     byte      nonzero
; Changes:      A and flags; IRQLOC and LC RAM's ROM_IRQ. Leaves LC bank 2
;               read-only, as crt0 does, and interrupts enabled.

initirq:
        ; Install both entry points, keeping the old vectors
        sei
        lda     IRQLOC
        sta     romnext+1
        lda     IRQLOC+1
        sta     romnext+2
        lda     #<romirq
        sta     IRQLOC
        lda     #>romirq
        sta     IRQLOC+1

        bit     LCBANK2           ; LC bank 2 read and write
        bit     LCBANK2
        lda     ROM_IRQ
        sta     lcnext+1
        lda     ROM_IRQ+1
        sta     lcnext+2
        lda     #<lcirq
        sta     ROM_IRQ
        lda     #>lcirq
        sta     ROM_IRQ+1
        bit     LC_BANK2_RO           ; LC bank 2 read only, as crt0 leaves it

        inc     installed
        cli
        rts

        .code

;-----------------------------------------------------------------------------
; doneirq: Put back the vectors initirq replaced. Called by the destructor of
; cc65's runtime/callirq.s.
;
; Input:        installed     byte      nonzero if initirq ran
;               romnext       JMP       the previous $3FE handler
;               lcnext        JMP       the previous LC RAM vector
; Output:       none
; Changes:      A and flags; IRQLOC and LC RAM's ROM_IRQ, if initirq ran.
;               Leaves LC bank 2 read-only and interrupts enabled.

doneirq:
        ; Restore the vectors, if initirq installed them
        lda     installed
        beq     :+
        sei
        lda     romnext+1
        sta     IRQLOC
        lda     romnext+2
        sta     IRQLOC+1
        bit     LCBANK2
        bit     LCBANK2
        lda     lcnext+1
        sta     ROM_IRQ
        lda     lcnext+2
        sta     ROM_IRQ+1
        bit     LC_BANK2_RO
        cli
        rts

:       rts

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; romirq: The interrupt handler while ROM is enabled. Entered from the
; Autostart ROM's IRQ handler through $3FE: runs the interruptors and returns
; from the interrupt if one handled it, else goes on to the previous handler.
;
; Input:        SAVEA         byte      the interrupted A, saved by ROM
;               X, Y          byte      as interrupted
; Output:       none
; Changes:      None for the interrupted code. The interruptors may change
;               what they handle.

romirq: cld
        txa
        pha
        tya
        pha
        jsr     callirq         ; C = handled
        pla
        tay
        pla
        tax
        bcc     :+
        lda     SAVEA
        rti
:       jmp     romnext         ; Not ours: previous handler, same state

;-----------------------------------------------------------------------------
; lcirq: The interrupt handler while LC RAM is enabled. Entered from LC RAM's
; $FFFE: runs the interruptors and returns from the interrupt if one handled
; it. A BRK, or an interrupt none handles, goes on to the previous vector
; (crt0's irq_6502).
;
; Input:        A, X, Y       byte      as interrupted
;               stack         byte      P and the return address, pushed by
;                                       the interrupt
; Output:       none
; Changes:      None for the interrupted code. The interruptors may change
;               what they handle.

lcirq:  pha
        txa
        pha
        tsx
        lda     $0103,x         ; P pushed by the interrupt
        and     #$10            ; B flag: BRK
        bne     pass
        tya
        pha
        cld
        jsr     callirq         ; C = handled
        pla
        tay
        bcc     pass            ; PLA and TAY leave C alone
        pla
        tax
        pla
        rti
pass:   pla                     ; Not ours, or BRK: where it went before
        tax
        pla
        jmp     lcnext

        .data

        ; In DATA, not BSS: crt0 clears BSS after the constructors run.
installed:      .byte   $00     ; Vectors installed

        ; The previous handlers, stored into absolute JMPs by initirq. An
        ; indirect JMP through a variable would fail if the variable ended
        ; up at $xxFF (the NMOS 6502's JMP ($xxFF) bug).
romnext:jmp     $0000           ; Previous $3FE handler
lcnext: jmp     $0000           ; Previous LC RAM vector (crt0's irq_6502)
