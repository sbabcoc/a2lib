;
; Reflow filter for stdio console output (DESIGN.md 3.7)
;
; void __fastcall__ reflow_on (unsigned char width);
; void reflow_off (void);
;
; reflow_on points COUT (cout.s) at the filter below, which word-wraps the
; text passing through it; reflow_off restores it. Linked only into
; programs that call them.
;
; width is the screen width to wrap for, 2-81; 0 means the visible width
; (a2_viewport: 40 on the stock screen and in the 40-column window, 80 on
; the VideoTerm). A line holds at most width - 1 characters, so the filter
; never relies on the display's own wrap at the edge, which differs
; between backends (immediate on the stock screen, delayed on the
; VideoTerm and in the window).
;
; Nothing is held back, so a prompt without a trailing space still appears
; before input: each character is printed at once, and the filter keeps
; the current word. When a word would overflow the line, the filter backs
; up over it, blanks it, and prints it again on the next line. A word that
; fills a whole line is broken there. A space that ends a full line becomes
; the line break, and spaces at the start of a line that the filter began
; are dropped; spaces after a carriage return are kept (indentation).
;
; The filter tracks the column itself, starting from wherex at reflow_on:
; after moving the cursor with conio, call reflow_on again. Typed input
; echoed by stdio passes through it too.
;
; COUT's callers rely on A, X and Y being preserved (write.s on X and Y,
; read.s on A), and write.s keeps its buffer in the zero page, so the
; filter preserves the registers and uses no zero page.
;

        .export         _reflow_on, _reflow_off

        .macpack        longbranch
        .import         a2_coutvec, a2_rawcout, a2_viewport, _wherex

REFLOW_MAX      = 81            ; Widest width; the word buffer holds 80

        .code

_reflow_on:
        cmp     #$00
        bne     :+
        jsr     a2_viewport
:       cmp     #2
        bcs     :+
        lda     #2
:       cmp     #REFLOW_MAX + 1
        bcc     :+
        lda     #REFLOW_MAX
:       sec
        sbc     #1
        sta     maxlen

        jsr     _wherex         ; Start at the cursor's column
        cmp     maxlen
        bcc     :+
        lda     maxlen
:       sta     col
        lda     #$00
        sta     wlen
        sta     wrapped

        lda     #<filter
        sta     a2_coutvec
        lda     #>filter
        sta     a2_coutvec+1
        rts

_reflow_off:
        lda     #<a2_rawcout
        sta     a2_coutvec
        lda     #>a2_rawcout
        sta     a2_coutvec+1
        rts

; ------------------------------------------------------------------------
; filter: COUT through the filter. The character is in A, bit 7 set.

filter: sta     savea
        stx     savex
        sty     savey
        cmp     #$8D
        jeq     cr
        cmp     #$A0
        jeq     space
        jcc     control

        ; Printable. If the line is full, start a new one first.
        lda     col
        cmp     maxlen
        bcc     put
        ldx     wlen
        beq     hard
        cpx     maxlen
        bcs     hard            ; The word fills the line: break it here

        ; Move the word to the next line: back up over it, blank it,
        ; break the line, and print it again
:       lda     #$88            ; Backspace
        jsr     a2_rawcout
        dex
        bne     :-
        ldx     wlen
:       lda     #$A0
        jsr     a2_rawcout
        dex
        bne     :-
        lda     #$8D
        jsr     a2_rawcout
        ldx     #$00
:       lda     wbuf,x
        jsr     a2_rawcout
        inx
        cpx     wlen
        bne     :-
        stx     col
        jmp     put

hard:   lda     #$8D
        jsr     a2_rawcout
        lda     #$00
        sta     col
        sta     wlen

put:    lda     savea
        jsr     a2_rawcout
        ldx     wlen            ; wlen <= col < maxlen <= 80
        sta     wbuf,x
        inc     wlen
        inc     col
        lda     #$00
        sta     wrapped
        beq     done            ; Branch always

        ; Space: ends the word
space:  lda     #$00
        sta     wlen
        lda     col
        cmp     maxlen
        bcc     :+
        lda     #$8D            ; Ends a full line: becomes the break
        jsr     a2_rawcout
        lda     #$00
        sta     col
        lda     #$80
        sta     wrapped
        bne     done            ; Branch always
:       lda     col
        bne     :+
        bit     wrapped         ; Leading space on a line the filter began
        bmi     done
:       lda     #$A0
        jsr     a2_rawcout
        inc     col
        bne     done            ; Branch always

        ; Carriage return
cr:     jsr     a2_rawcout
        lda     #$00
        sta     col
        sta     wlen
        sta     wrapped
        beq     done            ; Branch always

        ; Other controls pass through. Backspace moves back a column;
        ; the rest leave the column alone and end the word.
control:
        jsr     a2_rawcout
        cmp     #$88
        bne     :+
        lda     col
        beq     done
        dec     col
        lda     wlen
        beq     done
        dec     wlen
        jmp     done
:       lda     #$00
        sta     wlen

done:   lda     savea
        ldx     savex
        ldy     savey
        rts

        .bss

maxlen:         .res    1       ; Longest line: width - 1
col:            .res    1       ; Column of the next character
wlen:           .res    1       ; Length of the current word
wrapped:        .res    1       ; Bit 7: the filter began this line
wbuf:           .res    REFLOW_MAX - 1
savea:          .res    1
savex:          .res    1
savey:          .res    1
