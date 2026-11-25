;
; Oliver Schmidt, 2009-09-15
; Scott Babcock, 2026-11-12
;
; Startup code for DOS 3.3 programs, as cc65's without the ProDOS paths. The
; 6502 RESET and IRQ vectors in Language Card RAM are patched before the
; module constructors run, so that the interrupt handlers can replace the IRQ
; vector and chain to it. For details, see sections 6.1 and 7 of DESIGN.
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
        .include        "machine.inc"

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

;-----------------------------------------------------------------------------
; Start-up work done once, in the ONCE segment: save the zero page and the
; RESET vector, set up the C stack below HIMEM, point RESET at exit(), patch
; the RESET and IRQ vectors in LC RAM, run the module constructors, and copy
; the LC segment into LC RAM.
;
; Input:        HIMEM         word      BASIC's top of memory: the C stack's
;                                       top
;               SOFTEV        byte[3]   the RESET vector and its check byte
; Output:       c_sp          word      HIMEM
;               zpsave        byte[]    the zero page from c_sp, as at entry
;               rvsave        byte[3]   the RESET vector, as at entry
; Changes:      A, X and Y; SOFTEV and PWREDUP; LC RAM's ROM_RST and ROM_IRQ,
;               and the LC segment; HIGHDS, HIGHTR and LOWTR (bltu2); what the
;               constructors change. Leaves LC bank 2 read-only.
; Note:         The vectors are patched before the constructors run, so
;               initirq replaces this IRQ vector and chains to irq_6502.
;               cc65's startup code patches them afterward.

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
        bit     LC_ROM_WRAM
        bit     LC_ROM_WRAM

        lda     #<reset_6502
        ldx     #>reset_6502
        sta     ROM_RST
        stx     ROM_RST+1

        lda     #<irq_6502
        ldx     #>irq_6502
        sta     ROM_IRQ
        stx     ROM_IRQ+1

        ; Back to ROM for reading, LC write-protected, as at entry
        bit     LC_ROM_RO

        ; Call the module constructors.
        jsr     initlib

        ; Copy the LC segment to its destination
        ; Switch in LC bank 2 for W/O.
        bit     LC_ROM_WRAM
        bit     LC_ROM_WRAM

        ; Set the source start address.
        ; Aka __LC_LOAD__ iff segment LC exists.
        lda     #<(__ONCE_LOAD__ + __ONCE_SIZE__)
        ldy     #>(__ONCE_LOAD__ + __ONCE_SIZE__)
        sta     LOWTR
        sty     LOWTR+1

        ; Set the source last address.
        ; Aka __LC_LOAD__ + __LC_SIZE__ iff segment LC exists.
        lda     #<((__ONCE_LOAD__ + __ONCE_SIZE__) + (__LC_LAST__ - __LC_START__))
        ldy     #>((__ONCE_LOAD__ + __ONCE_SIZE__) + (__LC_LAST__ - __LC_START__))
        sta     HIGHTR
        sty     HIGHTR+1

        ; Set the destination last address.
        ; Aka __LC_RUN__ + __LC_SIZE__ iff segment LC exists.
        lda     #<__LC_LAST__
        ldy     #>__LC_LAST__
        sta     HIGHDS
        sty     HIGHDS+1

        ; Call into Applesoft Block Transfer Up -- which handles zero-
        ; sized blocks well -- to move the content of the LC memory area.
        jsr     bltu2

        ; Switch in LC bank 2 for R/O and return.
        bit     LC_BANK2_RO
        rts

; ------------------------------------------------------------------------

        .code

;-----------------------------------------------------------------------------
; Point the RESET vector at a routine. On RESET, the Autostart ROM jumps
; through the vector only if PWREDUP holds the MSB of the vector EOR #$A5;
; otherwise it takes RESET as a power-up, and reboots.
;
; Input:        A:X           word      the routine's address
; Output:       SOFTEV        word      the routine's address
;               PWREDUP       byte      MSB of the routine's address EOR #$A5
; Changes:      A and flags. X and Y are unchanged.
; Note:         cc65's exit code calls this too, so that a RESET during the
;               destructors still restores the vector and zero page. The rts
;               (return) is also the whole of cc65's rebootafterexit(); its
;               constructor points the JMP that ends the program (done) at
;               the Autostart ROM's PWRUP routine ($FAA6), which reboots.

reset:  stx     SOFTEV
        sta     SOFTEV+1
        eor     #$A5
        sta     PWREDUP
return: rts

;-----------------------------------------------------------------------------
; LC RAM's RESET vector: switch to ROM and take ROM's RESET vector.
;
; Changes:      Banks in ROM.

reset_6502:
        bit     LC_ROM_RO       ; Switch in ROM
        jmp     (ROM_RST)       ; Jump to ROM's RESET vector

;-----------------------------------------------------------------------------
; LC RAM's IRQ/BRK vector, as crt0 leaves it: switch to ROM and take ROM's
; IRQ/BRK vector. lcirq chains here for a BRK, or an interrupt no
; interruptor handles.
;
; Changes:      Banks in ROM, and leaves it in.

irq_6502:
        bit     LC_ROM_RO       ; Switch in ROM
        jmp     (ROM_IRQ)       ; Jump to ROM's IRQ/BRK vector

; ------------------------------------------------------------------------

        .data

        ; Final jump when we're done: callmain ends here after the
        ; destructors. Patched by exec() and rebootafterexit()
done:   jmp     DOSWARM

; ------------------------------------------------------------------------

        .segment        "INIT"

zpsave: .res    zpspace         ; byte[]: the zero page cc65 uses, at entry
rvsave: .res    3               ; byte[3]: the RESET vector, at entry
