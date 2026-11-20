;
; Scott Babcock, 2026-11-20
;
; int __fastcall__ file_set_type(const char *pathname, unsigned char type);
; int __fastcall__ file_set_auxtype(const char *pathname, unsigned int auxtype);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; either function fails to link instead, naming the symbol below.
;

        .export         _file_set_type, _file_set_auxtype
        .import         file_set_type_has_no_DOS_3_3_implementation
        .import         file_set_auxtype_has_no_DOS_3_3_implementation

_file_set_type  := file_set_type_has_no_DOS_3_3_implementation
_file_set_auxtype := file_set_auxtype_has_no_DOS_3_3_implementation
