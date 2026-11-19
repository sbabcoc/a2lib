;
; void __fastcall__ errprobe_arm (unsigned char reset);
;
; For test/errprobe.c: the hand-off half of exec() under DOS 3.3
; (DESIGN.md 5.10, steps 8, 9, 11 and 12), with a command DOS will fail.
; Copies the stub to the top of page 3, as stock exec.s does with its
; loader, and points crt0's final jump (done) at it. With reset nonzero,
; the stub undoes initprompt and clears ERRFLG before sending the command.
;

        .export         _errprobe_arm
        .import         done

        .include        "apple2.inc"

ERRFLG  := $D8                  ; Applesoft: bit 7 set while ONERR is active

        .code

_errprobe_arm:
        pha
        ldx     #size - 1
@copy:  lda     source,x
        sta     target,x
        dex
        bpl     @copy
        pla
        beq     :+
        lda     #$80
:       sta     flag_t
        lda     #<target
        ldx     #>target
        sta     done+1
        stx     done+2
        rts

        .rodata

; Runs at target, entered from done with ROM banked in. Only relative
; branches inside it; its data is addressed at target.

source:
        jsr     $03EA           ; Reconnect DOS's intercepts (DESIGN.md 5.10, 8)
        bit     flag_t
        bpl     @send
        lda     #$FF            ; As if typed at the ] prompt (5.10, 9)
        sta     CURLIN+1
        lda     #$DD            ; ']'
        sta     PROMPT
        lda     #$00
        sta     ERRFLG
@send:  ldx     #$00
@next:  lda     cmd_t,x
        beq     @done
        ora     #$80
        jsr     $FDED           ; COUT; DOS preserves X (it restores registers)
        inx
        bne     @next
@done:  jmp     DOSWARM         ; Reached only if DOS returns

flag:   .byte   $00
cmd:    .byte   $0D, $04, "BRUN NOSUCH,D2", $0D, $00

size    = * - source
target  = DOSWARM - size
flag_t  = flag - source + target
cmd_t   = cmd - source + target

        .assert target >= $0300, error
