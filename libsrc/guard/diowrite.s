;
; Scott Babcock, 2026-11-20
;
; unsigned char __fastcall__ dio_write (dhandle_t handle, unsigned sect_num, const void *buffer);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; dio_write (or dio_write_verify) fails to link instead, naming the symbol
; below.
;

        .export         _dio_write
        .import         dio_write_has_no_DOS_3_3_implementation

_dio_write      := dio_write_has_no_DOS_3_3_implementation
