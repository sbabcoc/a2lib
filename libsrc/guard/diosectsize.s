;
; Scott Babcock, 2026-11-20
;
; unsigned __fastcall__ dio_query_sectsize (dhandle_t handle);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which returns ProDOS's 512-byte block size; DOS 3.3 sectors
; are 256 bytes, and there is no DOS 3.3 dio_open to get a handle from. A
; program that calls dio_query_sectsize fails to link instead, naming the
; symbol below.
;

        .export         _dio_query_sectsize
        .import         dio_query_sectsize_has_no_DOS_3_3_implementation

_dio_query_sectsize := dio_query_sectsize_has_no_DOS_3_3_implementation
