;
; Scott Babcock, 2026-11-20
;
; char* __fastcall__ getdevicedir (unsigned char device, char* buf, size_t size);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; getdevicedir fails to link instead, naming the symbol below.
;

        .export         _getdevicedir
        .import         getdevicedir_has_no_DOS_3_3_implementation

_getdevicedir   := getdevicedir_has_no_DOS_3_3_implementation
