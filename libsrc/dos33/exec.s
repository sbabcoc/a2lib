;
; Scott Babcock, 2026-11-18
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
; for a bad path, a name with a comma (which a DOS command can't carry) or
; an A file with a cmdline, ENOENT and the other OPEN errors, ENOEXEC for a
; file that isn't B or A, ENOMEM if every DOS buffer is in use. After the
; hand-off, failures are DOS's.
;

        .export         _exec
        .import         popax, done, exit_with_params

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "apple2.inc"
        .include        "fm.inc"

; Shared storage
args            = ptr1          ; char*: cmdline
name_end        = tmp1          ; byte: just past the name's last character

ERRFLG  := $D8                  ; Applesoft: bit 7 set while ONERR is active
REM     = $B2                   ; Applesoft's REM token: mainargs' marker
CMDMAX  = 1 + 4 + 1 + NAME_LEN + 6 + 1 ; ^D BRUN sp name ,S7,D2 CR

        .code

;-----------------------------------------------------------------------------
; _exec: Run another program: int __fastcall__ exec (const char* progname,
; const char* cmdline). On success, doesn't return: the C library shuts down,
; as at exit, and DOS runs the program. Every check comes before that, so a
; failure leaves the program running.
;
; Input:        C stack       char*     progname: the program's path, a B or A
;                                       file
;               AX            char*     cmdline: its arguments for main (B
;                                       files), or NULL or ""
; Output:       AX            int       -1, if it returns
;               errno         int       EINVAL (a bad path, a name with a
;                                       comma, or an A file with a cmdline),
;                                       ENOENT and OPEN's other errors,
;                                       ENOEXEC (not a B or A file), ENOMEM
;                                       (no free DOS buffer)
;               __oserror     byte      the DOS 3.3 or library error, where
;                                       there is one
; Changes:      Y; args, name_end, fm_parmlist and ctlblock. Pops progname. If
;               it doesn't return: the stub's page-3 area (target), the stack
;               page (cmdline), BASIC's input buffer, and what exit() changes.

_exec:
        ; Store cmdline; get progname
        sta     cmdline
        stx     cmdline+1
        jsr     popax
        sta     progname
        stx     progname+1

        ; The file: name, existence and type, as sysremove.s does it
        jsr     fm_getfcb
        bcs     oserr
        jsr     fm_begin
        lda     progname
        ldx     progname+1
        jsr     fm_name
        bcs     free
        ldx     #$01            ; Don't allocate
        jsr     fm_open
        bcs     fail
        ldy     #FM_TYPE
        lda     (fm_parmlist),y
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
        sta     args+1
        lda     cmdline
        sta     args
        ldy     #$00
        lda     (args),y        ; ""?
        beq     stub
        lda     #EINVAL
        jmp     ___directerrno

        ; From here on nothing fails. Copy the stub, then build the
        ; command in it: $84, verb, space, name, slot, drive, $8D.
stub:   ldx     #code - 1
:       lda     source,x
        sta     target,x
        dex
        bpl     :-

        ldx     #$00
        lda     #HI_CTRL_D
        jsr     put
        lda     type
        cmp     #FMT_BINARY
        bne     :+
        lda     #'B' | $80
        jsr     put
:       ldy     #run - strings
        jsr     puts

        ; The name, without its padding
        ldy     #$00
@name:  lda     fm_namebuf,y    ; High bit already set
        jsr     put
        cmp     #HI_SPACE
        beq     :+
        stx     name_end        ; Just past the last character so far
:       iny
        cpy     #NAME_LEN
        bne     @name
        ldx     name_end

        ; ",S<slot>,D<drive>" and CR
        lda     fm_slot
        ora     #'0'
        sta     slotdigit
        lda     fm_drive
        ora     #'0'
        sta     drivedigit
        ldy     #suffix - strings
        jsr     puts
        stx     len_t           ; DOS stores ^D through CR; the tail follows
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
        sta     args+1
        lda     cmdline
        sta     args
@copy:  lda     (args),y
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

;-----------------------------------------------------------------------------
; put: Add a byte to the stub's command.
;
; Input:        A             byte      the byte
;               X             byte      its offset in the command
; Output:       X             byte      one higher
;               A             byte      unchanged
; Changes:      N and Z set from X. Y and C are unchanged.

put:    sta     cmd_t,x
        inx
        rts

;-----------------------------------------------------------------------------
; puts: Add one of the command's fixed parts to the stub's command, with the
; high bit set.
;
; Input:        Y             byte      the part's offset from strings: run -
;                                       strings or suffix - strings
;               X             byte      the offset in the command
; Output:       X             byte      past the part
; Changes:      A and Y.

puts:   lda     strings,y
        beq     :+
        ora     #$80
        jsr     put
        iny
        bne     puts            ; Branch always
:       rts

        .data

strings:                        ; The command's fixed parts, for puts
run:    .byte   "RUN ", $00     ; BRUN: 'B' put first
suffix: .byte   ",S"
slotdigit:
        .byte   "0,D"
drivedigit:
        .byte   "0", $0D, $00

        .rodata

;-----------------------------------------------------------------------------
; source: The stub, which exec() copies to target and done enters when the C
; library has shut down, with ROM banked in. Only relative branches inside it,
; and its data is addressed at target. Read-only here, as stock exec.s's
; loader is. It reconnects DOS, sets DOS's state to the ] prompt's, puts the
; argument tail after where DOS will store the command, prints the command,
; and ends in DOSWARM, where a B program that returns with RTS lands too.
;
; Input:        len_t         byte      the command's length, through its CR
;               cmd_t         char[]    the command: $84, verb, space, name,
;                                       slot, drive, $8D, $00
;               STACK_PAGE    char[]    cmdline: up to 127 bytes with its $00
; Output:       none
; Changes:      A, X and Y; CURLIN+1, PROMPT, ERRFLG and BASIC_BUF; DOS's
;               intercepts.
; Note:         It runs after the stack has been reset, with the C library
;               gone.

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

; After the code at target, not copied: exec() writes both
code    = * - source        ; Bytes copied
size    = code + 1 + CMDMAX + 1
target  = DOSWARM - size
len_t   = target + code     ; The command's length (1 byte)
cmd_t   = len_t + 1         ; The command and its terminator

        ; The stub and the tail stay out of each other's way, and the
        ; stub fits in $300-$3CF, as stock exec.s's loader does
        .assert target >= $0300, error
        .assert CMDMAX + 2 + 127 <= $100, error

        .bss

progname:       .res    2       ; char*: the program's path
cmdline:        .res    2       ; char*: its arguments, or NULL
type:           .res    1       ; byte: the program file's type (FMT_*)
