;
; sim65 stubs for reflow.s (test/sim/reflowsim.c): COUT as the vector
; reflow.s patches, an output routine that records what it is given, and
; settable a2_viewport and wherex results.
;
        .export         COUT, a2_coutvec, a2_rawcout, a2_viewport, _wherex
        .export         _out_buf, _out_len, _stub_view, _stub_x
        .export         _put, _put_regs

        .data
COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1
_stub_view:     .byte   40
_stub_x:        .byte   0
_out_len:       .word   0

        .bss
_out_buf:       .res    1024

        .code
; Record A, preserving A, X and Y like the real routines
a2_rawcout:
        pha
        txa
        pha
        tsx
        lda     $0102,x         ; The character
        ldx     _out_len
        sta     _out_buf,x      ; Under 256 bytes per case
        inc     _out_len
        pla
        tax
        pla
        rts

a2_viewport:
        lda     _stub_view
        rts

_wherex:
        lda     _stub_x
        ldx     #$00
        rts

; void __fastcall__ put (char c): c through COUT, bit 7 set
_put:   ora     #$80
        jmp     COUT

; unsigned char __fastcall__ put_regs (char c): 1 if COUT preserved A, X, Y
_put_regs:
        ora     #$80
        sta     want
        ldx     #$5A
        ldy     #$A5
        jsr     COUT
        cmp     want
        bne     :+
        cpx     #$5A
        bne     :+
        cpy     #$A5
        bne     :+
        lda     #$01
        ldx     #$00
        rts
:       lda     #$00
        tax
        rts

        .bss
want:   .res    1
