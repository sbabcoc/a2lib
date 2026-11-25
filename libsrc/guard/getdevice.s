;
; Scott Babcock, 2026-11-20
;
; A link-time guard for getfirstdevice() and getnextdevice(), in place of
; cc65's ProDOS version, which fails at run time under DOS 3.3. A program that
; calls either function fails to link instead, naming the symbol below. For
; details, see section 4.2 of DESIGN.
;

        .export         _getfirstdevice, _getnextdevice
        .import         getfirstdevice_has_no_DOS_3_3_implementation
        .import         getnextdevice_has_no_DOS_3_3_implementation

_getfirstdevice := getfirstdevice_has_no_DOS_3_3_implementation
_getnextdevice  := getnextdevice_has_no_DOS_3_3_implementation
