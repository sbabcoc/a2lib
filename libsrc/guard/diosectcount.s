;
; Scott Babcock, 2026-11-20
;
; unsigned __fastcall__ dio_query_sectcount (dhandle_t handle);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; dio_query_sectcount fails to link instead, naming the symbol below.
;

        .export         _dio_query_sectcount
        .import         dio_query_sectcount_has_no_DOS_3_3_implementation

_dio_query_sectcount := dio_query_sectcount_has_no_DOS_3_3_implementation
