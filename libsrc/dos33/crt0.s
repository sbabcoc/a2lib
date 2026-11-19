;
; Oliver Schmidt, 2009-09-15
;
; Startup code for cc65 (Apple2 version)
;
; DOS 3.3 version of libsrc/apple2/crt0.s from cc65. The ProDOS paths
; are removed. The 6502 RESET and IRQ vectors in Language Card RAM are
; patched before the module constructors run, so irq.s's initirq can
; replace the IRQ vector and chain to irq_6502.
;

        .export         done, return
        .export         zpsave, rvsave, reset
        .export         __STARTUP__ : absolute = 1      ; Mark as startup

        .import         initlib, _exit
        .import         zerobss, callmain
        .import         bltu2
        .import         __ONCE_LOAD__, __ONCE_SIZE__    ; Linker generated
        .import         __LC_START__, __LC_LAST__       ; Linker generated

        .include        "zeropage.inc"
        .include        "apple2.inc"

; ------------------------------------------------------------------------

        .segment        "STARTUP"

        ldx     #$FF
        txs                     ; Init stack pointer

        ; Save space by putting some of the start-up code in the ONCE segment,
        ; which can be re-used by the BSS segment, the heap and the C stack.
        jsr     init

        ; Clear the BSS data.
        jsr     zerobss

        ; Push the command-line arguments; and, call main().
        jmp     callmain

; ------------------------------------------------------------------------

        .segment        "ONCE"

        ; Save the zero-page locations that we need.
init:   ldx     #zpspace-1
:       lda     c_sp,x
        sta     zpsave,x
        dex
        bpl     :-

        ; Save the original RESET vector.
        ldx     #$02
:       lda     SOFTEV,x
        sta     rvsave,x
        dex
        bpl     :-

        ; Set up the C stack below BASIC's HIMEM.
        lda     HIMEM
        ldx     HIMEM+1
        sta     c_sp
        stx     c_sp+1

        ; RESET exits the program, closing its files.
        ldx     #<_exit
        lda     #>_exit
        jsr     reset           ; Setup RESET vector

        ; Switch in LC bank 2 for W/O.
        bit     $C081
        bit     $C081

        lda     #<reset_6502
        ldx     #>reset_6502
        sta     ROM_RST
        stx     ROM_RST+1

        lda     #<irq_6502
        ldx     #>irq_6502
        sta     ROM_IRQ
        stx     ROM_IRQ+1

        ; Back to ROM for reading, LC write-protected, as at entry
        bit     $C082

        ; Call the module constructors.
        jsr     initlib

        ; Copy the LC segment to its destination
        ; Switch in LC bank 2 for W/O.
        bit     $C081
        bit     $C081

        ; Set the source start address.
        ; Aka __LC_LOAD__ iff segment LC exists.
        lda     #<(__ONCE_LOAD__ + __ONCE_SIZE__)
        ldy     #>(__ONCE_LOAD__ + __ONCE_SIZE__)
        sta     $9B
        sty     $9C

        ; Set the source last address.
        ; Aka __LC_LOAD__ + __LC_SIZE__ iff segment LC exists.
        lda     #<((__ONCE_LOAD__ + __ONCE_SIZE__) + (__LC_LAST__ - __LC_START__))
        ldy     #>((__ONCE_LOAD__ + __ONCE_SIZE__) + (__LC_LAST__ - __LC_START__))
        sta     $96
        sty     $97

        ; Set the destination last address.
        ; Aka __LC_RUN__ + __LC_SIZE__ iff segment LC exists.
        lda     #<__LC_LAST__
        ldy     #>__LC_LAST__
        sta     $94
        sty     $95

        ; Call into Applesoft Block Transfer Up -- which handles zero-
        ; sized blocks well -- to move the content of the LC memory area.
        jsr     bltu2

        ; Switch in LC bank 2 for R/O and return.
        bit     $C080
        rts

; ------------------------------------------------------------------------

        .code

        ; Set up the RESET vector.
reset:  stx     SOFTEV
        sta     SOFTEV+1
        eor     #$A5
        sta     PWREDUP
return: rts

reset_6502:
        bit     $C082           ; Switch in ROM
        jmp     (ROM_RST)       ; Jump to ROM's RESET vector

irq_6502:
        bit     $C082           ; Switch in ROM
        jmp     (ROM_IRQ)       ; Jump to ROM's IRQ/BRK vector

; ------------------------------------------------------------------------

        .data

        ; Final jump when we're done
done:   jmp     DOSWARM         ; Patched by exec()

; ------------------------------------------------------------------------

        .segment        "INIT"

zpsave: .res    zpspace
rvsave: .res    3
