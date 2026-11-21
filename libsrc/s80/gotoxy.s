;
; Ullrich von Bassewitz, 06.08.1998
; Scott Babcock, 2026-11-12
;
; void __fastcall__ gotoxy (unsigned char x, unsigned char y);
; void __fastcall__ gotox (unsigned char x);
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
; on cc65's libsrc/apple2/gotoxy.s. With a VideoTerm, firmware GOTOXY;
; otherwise the model's cursor. As on the VideoTerm, an out-of-range column
; or row is ignored. Moving the cursor doesn't pan; writing or showing it
; does (DESIGN.md 3.6).
;

        .export         gotoxy, _gotoxy, _gotox
        .import         popa

        .include        "s80.inc"
        .include        "display.inc"
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
:       jmp     s80_goto

_gotox:
        tax                     ; Column; same row
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
        jmp     vt_goto
:       lda     s80_y
        jmp     s80_goto
