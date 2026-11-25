;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; clrscr() for the VideoTerm library: on the card, with the firmware's
; clear-screen. For details, see section 3.4 of DESIGN.
;

        .export         _clrscr
        .import         HOME

        .include        "vt.inc"

;-----------------------------------------------------------------------------
; Clear the screen and home the cursor: on the card, with the firmware's $0C;
; otherwise with the monitor's HOME.
;
; Signature:    void clrscr ()
; Overrides:    cc65's clrscr()
; Changes:      The screen and the cursor. On the card: A and flags.
;               Otherwise: A and Y, and the monitor's cursor cells.

_clrscr:
        bit     vt_active
        bmi     :+
        jmp     HOME
:       lda     #$0C
        jmp     vt_write
