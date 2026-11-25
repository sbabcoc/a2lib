;
; Scott Babcock, 2026-11-20
;
; A link-time guard for dio_close(), in place of cc65's ProDOS version, which
; fails at run time under DOS 3.3. A program that calls dio_close() fails to
; link instead, naming the symbol below. For details, see section 4.2 of
; DESIGN.
;

        .export         _dio_close
        .import         dio_close_has_no_DOS_3_3_implementation

_dio_close      := dio_close_has_no_DOS_3_3_implementation
