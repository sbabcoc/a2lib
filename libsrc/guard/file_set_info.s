;
; Scott Babcock, 2026-11-20
;
; A link-time guard for file_set_type() and file_set_auxtype(), in place of
; cc65's ProDOS version, which fails at run time under DOS 3.3. A program that
; calls either function fails to link instead, naming the symbol below. For
; details, see section 4.2 of DESIGN.
;

        .export         _file_set_type, _file_set_auxtype
        .import         file_set_type_has_no_DOS_3_3_implementation
        .import         file_set_auxtype_has_no_DOS_3_3_implementation

_file_set_type  := file_set_type_has_no_DOS_3_3_implementation
_file_set_auxtype := file_set_auxtype_has_no_DOS_3_3_implementation
