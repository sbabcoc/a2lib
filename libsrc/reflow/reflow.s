;
; Scott Babcock, 2026-11-13
;
; Word-wrapping stdio console output, with reflow_on() and reflow_off().
; Linked only into programs that call them.
;
; A line holds at most width - 1 characters, so the filter never relies on the
; display's own wrap at the edge, which differs between displays: immediate on
; the stock screen, delayed on the VideoTerm and on Soft-70.
;
; Nothing is held back, so a prompt without a trailing space still appears
; before input: each character is printed at once, and the filter keeps the
; current word. When a word would overflow the line, the filter backs up over
; it, blanks it, and prints it again on the next line. A word that fills a
; whole line is broken there. A space that ends a full line becomes the line
; break, and spaces at the start of a line the filter began are dropped;
; spaces after a carriage return are kept, for indentation.
;
; The filter tracks the column itself, from the cursor's at reflow_on(). Typed
; input echoed by stdio passes through it too. COUT's callers rely on A, X and
; Y being kept, and write() keeps its buffer in the zero page, so the filter
; keeps the registers and uses no zero page. For details, see section 3.7 of
; DESIGN.
;

        .export         _reflow_on, _reflow_off

        .macpack        longbranch
        .import         a2_coutvec, a2_rawcout, a2_viewport, _wherex

        .include        "machine.inc"

REFLOW_MAX      = 81            ; Widest width; the word buffer holds 80

        .code

;-----------------------------------------------------------------------------
; Word-wrap stdio console output, starting at the cursor's column: points COUT
; at filter. After moving the cursor with conio, call it again.
;
; Signature:    void __fastcall__ reflow_on (unsigned char width)
; Input:        A             unsigned char
;                                       screen width to wrap for, 2-81 (others
;                                       are clamped); 0 for the visible width
;                                       (a2_viewport)
; Output:       maxlen        byte      width - 1, the longest line
;               col           byte      the cursor's column (wherex), at most
;                                       maxlen
;               a2_coutvec    word      filter
; Changes:      A, X, Y and flags; wlen and wrapped.

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

;-----------------------------------------------------------------------------
; Stop word-wrapping: points COUT back at a2_rawcout.
;
; Signature:    void reflow_off ()
; Output:       a2_coutvec    word      a2_rawcout
; Changes:      A and flags. X and Y are unchanged.

_reflow_off:
        lda     #<a2_rawcout
        sta     a2_coutvec
        lda     #>a2_rawcout
        sta     a2_coutvec+1
        rts

;-----------------------------------------------------------------------------
; COUT while reflow is on, word-wrapping as described above.
;
; Input:        A             char      the character, bit 7 set
;               col           byte      the column of the next character
;               wlen          byte      the current word's length
;               wrapped       byte      bit 7: the filter began this line
; Output:       col           byte      updated
;               wlen          byte      updated
;               wrapped       byte      updated
; Changes:      Flags; wbuf; the screen. A, X and Y are unchanged, and no zero
;               page is used (see above).

filter: sta     savea
        stx     savex
        sty     savey
        cmp     #HI_CR
        jeq     cr
        cmp     #HI_SPACE
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
:       lda     #HI_BS
        jsr     a2_rawcout
        dex
        bne     :-
        ldx     wlen
:       lda     #HI_SPACE
        jsr     a2_rawcout
        dex
        bne     :-
        lda     #HI_CR
        jsr     a2_rawcout
        ldx     #$00
:       lda     wbuf,x
        jsr     a2_rawcout
        inx
        cpx     wlen
        bne     :-
        stx     col
        jmp     put

hard:   lda     #HI_CR
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
        lda     #HI_CR          ; Ends a full line: becomes the break
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
:       lda     #HI_SPACE
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
        cmp     #HI_BS
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
wbuf:           .res    REFLOW_MAX - 1  ; char[80]: the current word
savea:          .res    1       ; filter's A, X and Y, given back
savex:          .res    1
savey:          .res    1
