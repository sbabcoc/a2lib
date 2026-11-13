;
; void __fastcall__ gotoxy (unsigned char x, unsigned char y);
; void __fastcall__ gotox (unsigned char x);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/gotoxy.s. With a VideoTerm, firmware GOTOXY; otherwise the
; window's cursor. As on the VideoTerm, an out-of-range column or row is
; ignored. Moving the cursor doesn't pan; writing or showing it does
; (DESIGN.md 3.6).
;

        .export         gotoxy, _gotoxy, _gotox
        .import         popa

        .include        "win.inc"
        .include        "vt.inc"

gotoxy:
        jsr     popa            ; Get Y

_gotoxy:
        pha                     ; Row
        jsr     popa            ; Column
        tax
        pla
        bit     vt_active
        bpl     :+
        jmp     vt_goto
:       jmp     win_goto

_gotox:
        tax                     ; Column; same row
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
        jmp     vt_goto
:       lda     win_y
        jmp     win_goto
