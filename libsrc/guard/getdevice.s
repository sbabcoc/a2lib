;
; Scott Babcock, 2026-11-20
;
; unsigned char getfirstdevice (void);
; unsigned char __fastcall__ getnextdevice (unsigned char device);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; either function fails to link instead, naming the symbol below.
;

        .export         _getfirstdevice, _getnextdevice
        .import         getfirstdevice_has_no_DOS_3_3_implementation
        .import         getnextdevice_has_no_DOS_3_3_implementation

_getfirstdevice := getfirstdevice_has_no_DOS_3_3_implementation
_getnextdevice  := getnextdevice_has_no_DOS_3_3_implementation
