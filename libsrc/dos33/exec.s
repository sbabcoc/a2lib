;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; int __fastcall__ exec (const char* progname, const char* cmdline);
;
; Replaces libsrc/apple2/exec.s from cc65 (DESIGN.md 5.10). Keeps stock
; exec()'s structure: check the program file, shut the C library down
; through exit_with_params, and finish in a stub at the top of page 3.
; Instead of stock's ProDOS loader, the stub sends DOS 3.3 a command
; through COUT: BRUN for a B file, RUN for an A file, with the name's slot
; and drive written out. A non-empty cmdline follows the command in page 2
; (after DOS's copy of the command at $200) as $00 $B2 cmdline $00, for
; a2lib's mainargs.s; an A file takes no cmdline (EINVAL).
;
; Fails, returning -1 with errno set, before anything is shut down: EINVAL
; for a bad path,
; a name with a comma (which a DOS command can't carry) or an A file with
; a cmdline, ENOENT and the other OPEN errors, ENOEXEC
; for a file that isn't B or A, ENOMEM if the temporary control block
; can't be allocated. After the hand-off, failures are DOS's.
;

        .export         _exec
        .import         popax, done, exit_with_params

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "apple2.inc"
        .include        "fm.inc"

ERRFLG  := $D8                  ; Applesoft: bit 7 set while ONERR is active
REM     = $B2                   ; Applesoft's REM token: mainargs' marker
CMDMAX  = 1 + 4 + 1 + NAME_LEN + 6 + 1 ; ^D BRUN sp name ,S7,D2 CR

        .code

_exec:
        ; Store cmdline; get progname
        sta     cmdline
        stx     cmdline+1
        jsr     popax
        sta     progname
        stx     progname+1

        ; The file: name, existence and type, as sysremove.s does it
        jsr     fm_tempfcb
        bcs     oserr
        jsr     fm_begin
        lda     progname
        ldx     progname+1
        jsr     fm_name
        bcs     free
        lda     #$00
        ldy     #FM_RECORD
        sta     (ptr3),y
        iny
        sta     (ptr3),y
        ldy     #FM_CALL
        lda     #FMC_OPEN
        sta     (ptr3),y
        ldx     #$01            ; Don't allocate
        jsr     fm_call
        bcs     fail
        ldy     #FM_TYPE
        lda     (ptr3),y
        and     #FMT_TYPE_MASK
        sta     type
        lda     #FMC_CLOSE
        jsr     fm_simple
        lda     #$00            ; No error
        beq     free            ; Branch always
fail:   jsr     fm_maperr
free:   jsr     fm_freefcb      ; Preserves A
        cmp     #$01            ; C = (A <> 0)
        bcc     verb
oserr:  jmp     ___mappederrno

        ; A name with a comma can't be given to a DOS command: its parser
        ; ends the name there. The File Manager accepts one (DESIGN.md 5.5).
verb:   ldx     #NAME_LEN-1
@comma: lda     fm_namebuf,x
        cmp     #',' | $80
        beq     @syntax
        dex
        bpl     @comma

        ; BRUN for B, RUN for A (without a cmdline)
        lda     type
        cmp     #FMT_BINARY
        beq     stub
        cmp     #FMT_APPLESOFT
        beq     :+
        lda     #DOSERR_TYPE    ; FILE TYPE MISMATCH -> ENOEXEC
        bne     oserr           ; Branch always
@syntax:
        lda     #DOSERR_SYNTAX  ; -> EINVAL
        bne     oserr           ; Branch always
:       lda     cmdline+1       ; NULL?
        beq     stub
        sta     ptr1+1
        lda     cmdline
        sta     ptr1
        ldy     #$00
        lda     (ptr1),y        ; ""?
        beq     stub
        lda     #EINVAL
        jmp     ___directerrno

        ; From here on nothing fails. Copy the stub, then build the
        ; command in it: $84, verb, space, name, slot, drive, $8D.
stub:   ldx     #size - 1
:       lda     source,x
        sta     target,x
        dex
        bpl     :-

        ldx     #$00
        lda     #HI_CTRL_D
        jsr     put
        ldy     #$00
        lda     type
        cmp     #FMT_BINARY
        bne     :+
        lda     #'B'
        jsr     putlo
:       lda     verbrun,y
        beq     :+
        jsr     putlo
        iny
        bne     :-              ; Branch always

        ; The name, without its padding
:       ldy     #NAME_LEN
:       dey
        lda     fm_namebuf,y
        cmp     #HI_SPACE
        beq     :-
        sty     tmp1            ; Index of the last character
        ldy     #$00
:       lda     fm_namebuf,y    ; High bit already set
        jsr     put
        iny
        cpy     tmp1
        bcc     :-
        beq     :-

        lda     #','
        jsr     putlo
        lda     #'S'
        jsr     putlo
        lda     fm_slot
        jsr     putdigit
        lda     #','
        jsr     putlo
        lda     #'D'
        jsr     putlo
        lda     fm_drive
        jsr     putdigit
        lda     #HI_CR
        jsr     put
        stx     len_t           ; DOS stores ^D through CR: the tail goes after
        lda     #$00
        sta     cmd_t,x

        ; Point of no return. As stock exec.s: reset the stack, keep up to
        ; 127 bytes of cmdline (terminator included) in the stack page, and
        ; finish in the stub after the C library has shut down.
        ldx     #$FF
        txs
        ldy     #$00
        lda     cmdline+1       ; NULL?
        beq     @store          ; Yes, store as '\0'
        sta     ptr1+1
        lda     cmdline
        sta     ptr1
@copy:  lda     (ptr1),y
@store: sta     STACK_PAGE,y
        beq     @handoff        ; '\0' stored, done
        iny
        cpy     #$7E
        bcc     @copy
        lda     #$00            ; '\0'
        beq     @store          ; Branch always

@handoff:
        lda     #<target
        ldx     #>target
        sta     done+1
        stx     done+2
        jmp     exit_with_params

; put: store A at cmd_t + X, X + 1. putlo: the same with the high bit set.
; Preserve Y.

putlo:  ora     #$80
put:    sta     cmd_t,x
        inx
        rts

; putdigit: put the decimal digit (0-9) in A. Preserves Y.

putdigit:
        ora     #'0' | $80
        bne     put             ; Branch always

        .rodata

verbrun:
        .byte   "RUN ", $00     ; BRUN: 'B' put first

; ------------------------------------------------------------------------
; The stub. Runs at target, entered from done with ROM banked in: only
; relative branches inside it, and its data is addressed at target.

source:
        jsr     DOS_CONNECT     ; Reconnect DOS's intercepts

        ; CR first, while DOS still sees a running program (initprompt):
        ; DOS's state 2 or 3 goes to state 0 on it without collecting it
        lda     #HI_CR
        jsr     MON_COUT

        ; Then DOS's state as when the command is typed at the ] prompt,
        ; so a DOS error ends there instead of in Applesoft (DESIGN.md 5.10)
        lda     #$FF
        sta     CURLIN+1
        lda     #$DD            ; ']'
        sta     PROMPT
        lda     #$00
        sta     ERRFLG

        ; The argument tail, after where DOS will store the command
        lda     STACK_PAGE
        beq     @send
        ldy     len_t
        lda     #$00            ; Marker
        sta     BASIC_BUF,y
        iny
        lda     #REM
        sta     BASIC_BUF,y
        iny
        ldx     #$00
@tail:  lda     STACK_PAGE,x
        sta     BASIC_BUF,y
        beq     @send
        inx
        iny
        bne     @tail

@send:  ldx     #$00
@next:  lda     cmd_t,x
        beq     @done
        jsr     MON_COUT        ; DOS restores the registers
        inx
        bne     @next
@done:  jmp     DOSWARM         ; A B program that returns with RTS

len:    .byte   $00
cmd:    .res    CMDMAX + 1      ; The command and its terminator

size    = * - source
target  = DOSWARM - size
len_t   = len - source + target
cmd_t   = cmd - source + target

        ; The stub and the tail stay out of each other's way, and the
        ; stub fits in $300-$3CF, as stock exec.s's loader does
        .assert target >= $0300, error
        .assert CMDMAX + 2 + 127 <= $100, error

        .bss

progname:       .res    2
cmdline:        .res    2
type:           .res    1
