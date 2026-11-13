;
; Interrupt tests for the DOS 3.3 IRQ handling (DESIGN.md section 6)
;
; unsigned char irq_lc (void);
; unsigned char irq_rom (void);
;
; No emulated card raises IRQ yet, so these simulate one: push the return
; address and a status byte with B clear, as the CPU does on an interrupt,
; then jump through the vector at $FFFE.
;
;   irq_lc:  with LC RAM enabled for reading (cc65's normal state), the
;            vector comes from LC RAM and enters lcirq.
;   irq_rom: with ROM switched in (as during COUT or a File Manager call),
;            it comes from ROM and enters the Autostart ROM's IRQ handler,
;            which saves A in $45 and jumps through $3FE to romirq.
;
; Each returns a bit set per check that passed:
;   IRQ_HANDLED   the interruptor below was called and handled it
;   IRQ_BANKING   the same bank (LC RAM or ROM) is enabled after the RTI
;   IRQ_REGS      A, X and Y are unchanged after the RTI
;
; Declaring an interruptor also makes every test run go through initirq
; and doneirq, so the file tests run with the handlers installed.
;

        .export         _irq_lc, _irq_rom
        .interruptor    counter

        .include        "apple2.inc"

IRQ_HANDLED = $01
IRQ_BANKING = $02
IRQ_REGS    = $04

TEST_A = $5A
TEST_X = $A5
TEST_Y = $3C

        .segment        "LOWCODE"

; The interruptor: handles the interrupt only when armed, so a stray real
; interrupt isn't counted.

counter:
        lda     armed
        beq     :+              ; C clear: not ours
        lda     #$00
        sta     armed
        inc     count
        sec                     ; Handled
:       rts

_irq_rom:
        bit     $C082           ; ROM
        jsr     simulate
        bit     $C080           ; LC bank 2, read only (cc65's state)
        lda     result
        ldx     #$00
        rts

_irq_lc:
        jsr     simulate
        lda     result
        ldx     #$00
        rts

; simulate: one interrupt through the vector at $FFFE as currently
; enabled. Sets result.

simulate:
        lda     ROM_IRQ         ; Vector before, to compare after
        sta     before
        lda     ROM_IRQ+1
        sta     before+1
        lda     count
        sta     startcount
        lda     #$01
        sta     armed

        ; What the CPU pushes: PCH, PCL, then P with B clear
        lda     #>back
        pha
        lda     #<back
        pha
        php
        pla
        and     #<~$10          ; B clear: an interrupt, not BRK
        pha
        lda     #TEST_A
        ldx     #TEST_X
        ldy     #TEST_Y
        sei                     ; The CPU sets I on interrupt entry
        jmp     (ROM_IRQ)

back:   sta     sava            ; RTI returns here
        stx     savx
        sty     savy

        lda     #$00
        sta     result
        lda     count           ; Handled: count advanced by one
        sec
        sbc     startcount
        cmp     #$01
        bne     :+
        lda     #IRQ_HANDLED
        sta     result
:       lda     ROM_IRQ         ; Banking: same vector visible as before
        cmp     before
        bne     :+
        lda     ROM_IRQ+1
        cmp     before+1
        bne     :+
        lda     result
        ora     #IRQ_BANKING
        sta     result
:       lda     sava            ; Registers
        cmp     #TEST_A
        bne     :+
        lda     savx
        cmp     #TEST_X
        bne     :+
        lda     savy
        cmp     #TEST_Y
        bne     :+
        lda     result
        ora     #IRQ_REGS
        sta     result
:       rts

        .bss

armed:          .res    1
count:          .res    1
startcount:     .res    1
before:         .res    2
sava:           .res    1
savx:           .res    1
savy:           .res    1
result:         .res    1
