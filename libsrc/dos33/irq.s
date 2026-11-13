;
; IRQ handling for the cc65 apple2 target, with DOS 3.3 support
;
; Replaces libsrc/apple2/irq.s from cc65 (Oliver Schmidt, 2012-11-17),
; whose ProDOS path is kept unchanged: under ProDOS, initirq allocates an
; interrupt vector table entry as before. Under DOS 3.3, where the stock
; module fails with "FAILED TO ALLOC INTERRUPT", it installs handlers
; itself. See DESIGN.md section 6.
;
; A 16K Language Card on a II+ has no switch that reports whether its RAM
; or the ROM is enabled for reading, so a handler can't save and restore
; that state. As ProDOS does, the DOS 3.3 path tells the state from the
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
        .import         callirq, __dos_type, _exit

        .include        "apple2.inc"

        .macpack        apple2

IRQLOC  := $03FE                ; Monitor's maskable-interrupt vector
SAVEA   := $45                  ; Where the ROM IRQ handler saves A

        .segment        "ONCE"

initirq:
        ; Check for ProDOS
        lda     __dos_type
        beq     dos33

        ; Allocate interrupt vector table entry
        jsr     $BF00           ; MLI call entry point
        .byte   $40             ; Alloc interrupt
        .addr   i_param
        bcs     prterr

        ; Enable interrupts, as old ProDOS versions (i.e. 1.1.1)
        ; jump to SYS and BIN programs with interrupts disabled.
        cli
        rts

        ; DOS 3.3: install both entry points, keeping the old vectors
dos33:  sei
        lda     IRQLOC
        sta     romnext+1
        lda     IRQLOC+1
        sta     romnext+2
        lda     #<romirq
        sta     IRQLOC
        lda     #>romirq
        sta     IRQLOC+1

        bit     $C083           ; LC bank 2 read and write
        bit     $C083
        lda     ROM_IRQ
        sta     lcnext+1
        lda     ROM_IRQ+1
        sta     lcnext+2
        lda     #<lcirq
        sta     ROM_IRQ
        lda     #>lcirq
        sta     ROM_IRQ+1
        bit     $C080           ; LC bank 2 read only, as crt0 leaves it

        inc     installed
        cli
        rts

        ; Print error message and exit
prterr: ldx     #msglen-1
:       lda     errmsg,x
        jsr     $FDED           ; COUT
        dex
        bpl     :-
        jmp     _exit

errmsg: .ifdef  __APPLE2ENH__
        scrcode $0D, "tpurretni colla ot deliaF", $0D
        .else
        scrcode $0D, "TPURRETNI COLLA OT DELIAF", $0D
        .endif

msglen = * - errmsg

        .code

doneirq:
        ; DOS 3.3: restore the vectors, if initirq installed them
        lda     installed
        beq     prodos
        sei
        lda     romnext+1
        sta     IRQLOC
        lda     romnext+2
        sta     IRQLOC+1
        bit     $C083
        bit     $C083
        lda     lcnext+1
        sta     ROM_IRQ
        lda     lcnext+2
        sta     ROM_IRQ+1
        bit     $C080
        cli
        rts

prodos:
        ; Check for valid interrupt vector table entry number which
        ; IS necessary as this gets called even if initirq failed.
        lda     int_num
        beq     :+

        ; Deallocate interrupt vector table entry
        dec     i_param         ; Adjust parameter count
        jsr     $BF00           ; MLI call entry point
        .byte   $41             ; Dealloc interrupt
        .addr   i_param
:       rts

        .segment        "LOWCODE"

intptr:
        ; ProDOS TechRefMan, chapter 6.2:
        ; "Each installed routine must begin with a CLD instruction."
        cld

        ; Call interruptors and check for success
        jsr     callirq
        bcc     :+

        ; ProDOS TechRefMan, chapter 6.2:
        ; "When the routine that can process the interrupt is called, it
        ;  should ... return (via an RTS) with the carry flag clear."
        clc
        rts

        ; ProDOS TechRefMan, chapter 6.2:
        ; "When a routine that cannot process the interrupt is called,
        ;  it should return (via an RTS) with the cary flag set ..."
:       sec
        rts

; DOS 3.3, ROM enabled: entered from the ROM IRQ handler through $3FE,
; with A saved in $45 and X and Y intact.

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

; DOS 3.3, LC RAM enabled: entered from the vector at $FFFE in LC RAM,
; with A, X and Y as interrupted.

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
installed:      .byte   $00     ; DOS 3.3 vectors installed

        ; The previous handlers, stored into absolute JMPs by initirq. An
        ; indirect JMP through a variable would fail if the variable ended
        ; up at $xxFF (the NMOS 6502's JMP ($xxFF) bug).
romnext:jmp     $0000           ; Previous $3FE handler
lcnext: jmp     $0000           ; Previous LC RAM vector (crt0's irq_6502)

        ; MLI parameter list for (de)alloc interrupt
i_param:.byte   $02             ; param_count
int_num:.byte   $00             ; int_num
        .addr   intptr          ; int_code

