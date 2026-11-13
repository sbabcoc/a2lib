;
; COUT routine
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/cout.s (Oliver Schmidt). Console output goes to the
; VideoTerm or into the window. Linking this module (all console output
; does) also links vt.s and win.s, whose constructors set up the display.
;

        .export         COUT

        .include        "win.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

COUT:
        bit     vt_active
        bpl     :+
        jmp     vt_write
:       jmp     win_cout
