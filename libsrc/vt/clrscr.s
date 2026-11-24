;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; void clrscr (void);
;
; VideoTerm backend (a2lib-vt.lib): modified copy of
; libsrc/apple2/clrscr.s from cc65; if the card is in use, clears its
; screen and homes its cursor (firmware $0C) instead (DESIGN.md 3.4).
;

        .export         _clrscr
        .import         HOME

        .include        "vt.inc"

;-----------------------------------------------------------------------------
; _clrscr: Clear the screen and home the cursor: void clrscr (void). On the
; card, with the firmware's $0C; otherwise with the monitor's HOME.
;
; Input:        none
; Output:       none
; Changes:      The screen and the cursor. On the card: A and flags.
;               Otherwise: A and Y, and the monitor's cursor cells.

_clrscr:
        bit     vt_active
        bmi     :+
        jmp     HOME
:       lda     #$0C
        jmp     vt_write
