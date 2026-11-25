;
; Scott Babcock, 2026-11-20
;
; A link-time guard for dio_query_sectsize(), in place of cc65's ProDOS
; version, which returns ProDOS's 512-byte block size; DOS 3.3 sectors are 256
; bytes, and there is no DOS 3.3 dio_open() to get a handle from. A program
; that calls dio_query_sectsize() fails to link instead, naming the symbol
; below. For details, see section 4.2 of DESIGN.
;

        .export         _dio_query_sectsize
        .import         dio_query_sectsize_has_no_DOS_3_3_implementation

_dio_query_sectsize := dio_query_sectsize_has_no_DOS_3_3_implementation
