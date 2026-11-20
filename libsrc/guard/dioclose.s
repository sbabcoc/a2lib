;
; Scott Babcock, 2026-11-20
;
; unsigned char __fastcall__ dio_close (dhandle_t handle);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; dio_close fails to link instead, naming the symbol below.
;

        .export         _dio_close
        .import         dio_close_has_no_DOS_3_3_implementation

_dio_close      := dio_close_has_no_DOS_3_3_implementation
