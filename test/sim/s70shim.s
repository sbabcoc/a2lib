; sim65 stubs for s70.s: cc65's uppercasemask (apple2 target only), and C
; names for the library's internals that s70sim.c checks
        .export         uppercasemask
        .export         _s70_curshow, _s70_curhide, _s80_buf
        .export         _run_destructors, _s80_left_addr
        .import         s70_curshow, s70_curhide, s80_buf, s80_left
        .import         donelib

_s80_buf        = s80_buf

        .data
uppercasemask:  .byte   $DF

        .code
_s70_curshow:   jmp     s70_curshow
_s70_curhide:   jmp     s70_curhide
_run_destructors:
                jmp     donelib         ; As at exit

        .rodata
_s80_left_addr: .addr   s80_left
