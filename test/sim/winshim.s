; sim65 stubs for win.s: no VideoTerm, no-op monitor routines
        .export         vt_active, HOME, VTABZ, vt_write, vt_goto, vt_r10, vt_screen
        .data
vt_active:      .byte   0
        .code
HOME:
VTABZ:
vt_write:
vt_goto:
vt_r10:
vt_screen:
        rts
