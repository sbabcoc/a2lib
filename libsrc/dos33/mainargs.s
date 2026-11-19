; mainargs.s
;
; DOS 3.3 version of libsrc/apple2/mainargs.s from cc65 (DESIGN.md 5.10).
; argv[0] is "": DOS 3.3 doesn't keep the program's name. Arguments come
; from the REM on the command line, or from the tail exec() leaves after
; its command in page 2: exec()'s stub prints the command, which DOS
; stores at $200 from its Ctrl-D through its CR, and puts
; "$00 REM cmdline $00" right after the CR. A typed line has the high
; bit set and doesn't begin with Ctrl-D, so it can't match; the $00 is
; cleared once the arguments are taken.
;
; Ullrich von Bassewitz, 2003-03-07
; Based on code from Stefan A. Haubenthal <polluks@web.de>, 2003-11-08
; Greg King, 2003-05-18
; Stefan Haubenthal, 2005-01-07
; Oliver Schmidt, 2005-04-05
;
; Scan a group of arguments that are in BASIC's input-buffer.
; Build an array that points to the beginning of each argument.
; Send, to main(), that array and the count of the arguments.

; Command-lines look like these lines:
;
; call2051
; call2051 : rem
; call2051:rem arg1 " arg 2 is quoted "  arg3 "" arg5
;
; "call" and "rem" are entokenned; the args. are not. Leading and trailing
; spaces outside of quotes are ignored.

; TO-DO:
; Add a control-character quoting mechanism.

        .constructor    initmainargs, 24
        .import         __argc, __argv

        .include        "zeropage.inc"
        .include        "apple2.inc"

; Maximum number of arguments allowed in the argument table.
; (An argument contains a comma, at least.)

MAXARGS = 10

; The arguments may use 127 characters, including the terminating zero, as
; in stock cc65 (and exec(), which passes at most that many).

BUF_LEN = 127

REM       = $B2                 ; BASIC token-code

        .include        "machine.inc"   ; BASIC_BUF, HI_CTRL_D, HI_CR, HI_SPACE

; Get possible command-line arguments. Goes into the special ONCE segment,
; which may be reused after the startup code is run.

        .segment        "ONCE"

initmainargs:

        inc     __argc          ; argc always is equal to, at least, 1

; Take exec()'s arguments if it left them.

        jsr     execargs        ; C clear: X indexes them in BASIC_BUF
        bcc     copy

; Find the "rem" token.

        ldx     #$00
:       lda     BASIC_BUF,x
        beq     done            ; No "rem" -> no args
        inx
        cmp     #REM
        bne     :-

; Copy the command-line out of BASIC's input buffer, which the next line
; of input overwrites.

copy:   ldy     #$00
        sty     buffer + BUF_LEN - 1
:       lda     BASIC_BUF,x
        sta     buffer,y
        inx
        iny
        cpy     #BUF_LEN - 1    ; Keep the terminating zero intact
        bcc     :-

; Start processing the arguments.

        ldx     #$00
        ldy     #$01 * 2        ; Start with argv[1]

; Find the next argument. Stop if the end of the string or a character with the
; hibit set is reached. The latter means the buffer holds a typed line, not a
; line parsed by BASIC, where a '2' ($32+$80 = $B2) looks like the REM token.

next:   lda     buffer,x
        beq     done
        bmi     done
        inx
        cmp     #' '            ; Skip leading spaces
        beq     next

; Found start of next argument. We've incremented the pointer in X already, so
; it points to the second character of the argument. This is useful since we
; will check now for a quoted argument, in which case we will have to skip this
; first character.

        cmp     #'"'            ; Is the argument quoted?
        beq     :+              ; Jump if so
        dex                     ; Reset pointer to first argument character
        lda     #' '            ; A space ends the argument
:       sta     tmp1            ; Set end of argument marker

; Now store a pointer to the argument into the next slot.

        txa                     ; Get low byte
        clc
        adc     #<buffer
        sta     argv,y          ; argv[y] = &arg
        iny
        lda     #$00
        adc     #>buffer
        sta     argv,y
        iny
        inc     __argc          ; Found another arg

; Search for the end of the argument.

:       lda     buffer,x
        beq     done
        inx
        cmp     tmp1
        bne     :-

; We've found the end of the argument. X points one character behind it, and
; A contains the terminating character. To make the argument a valid C string,
; replace the terminating character by a zero.

        lda     #$00
        sta     buffer-1,x

; Check if the maximum number of command-line arguments is reached. If not,
; parse the next one.

        lda     __argc          ; Get low byte of argument count
        cmp     #MAXARGS        ; Maximum number of arguments reached?
        bcc     next            ; Parse next one if not

; (The last vector in argv[] already is NULL.)

done:   lda     #<argv
        ldx     #>argv
        sta     __argv
        stx     __argv+1
        rts

; execargs: exec()'s arguments in BASIC_BUF? If so, clear the marker and
; return carry clear with X indexing the first byte after the REM.
; Otherwise carry set.

execargs:
        lda     BASIC_BUF       ; The command begins with Ctrl-D
        cmp     #HI_CTRL_D
        bne     none
        ldx     #$00
:       inx
        bmi     none            ; exec()'s command is far shorter
        lda     BASIC_BUF,x
        cmp     #HI_CR          ; Its CR
        bne     :-
        lda     BASIC_BUF+1,x   ; Then $00 and REM
        bne     none
        lda     BASIC_BUF+2,x
        cmp     #REM
        bne     none
        lda     #HI_SPACE       ; Clear the marker
        sta     BASIC_BUF+1,x
        inx                     ; Past the CR, the marker and the REM
        inx
        inx
        clc
        rts
none:   sec
        rts

        .rodata

empty:  .byte   $00             ; argv[0]

        .data

; char* argv[MAXARGS+1] = {""};

argv:   .addr   empty
        .res    MAXARGS * 2

        .segment        "INIT"

buffer: .res    BUF_LEN
