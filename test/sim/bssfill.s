; sim65 support for gaugesim.c: the model's buffer in BSS must be left to
; crt0. On the Apple II, apple2.cfg starts BSS where ONCE starts and crt0
; clears BSS after the constructors run, so a constructor that writes the
; buffer overwrites the constructors' own code (DESIGN.md 10.12). sim65's
; crt0 clears BSS first, so this constructor, run before the model's,
; marks the buffer; gaugesim.c checks that the mark survives startup.
        .export         _model_clear, _s80_buf
        .import         s80_buf, s80_clear

_s80_buf        = s80_buf
        .constructor    mark, 20

        .segment        "ONCE"
mark:   lda     #$EA
        ldx     #$00
:       .repeat 8, i
        sta     s80_buf + i * 240,x
        .endrepeat
        inx
        cpx     #240
        bne     :-
        rts

        .code
_model_clear:
        jmp     s80_clear
