;
; Kevin Ruland
;
; void clrscr (void);
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/clrscr.s from cc65; if the card is in use, clears its
; screen and homes its cursor (firmware $0C) instead (DESIGN.md 3.4).
;

        .export         _clrscr
        .import         HOME

        .include        "vt.inc"

_clrscr:
        bit     vt_active
        bmi     :+
        jmp     HOME
:       lda     #$0C
        jmp     vt_write
