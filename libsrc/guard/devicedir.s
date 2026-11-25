;
; Scott Babcock, 2026-11-20
;
; A link-time guard for getdevicedir(), in place of cc65's ProDOS version,
; which fails at run time under DOS 3.3. A program that calls getdevicedir()
; fails to link instead, naming the symbol below. For details, see section 4.2
; of DESIGN.
;

        .export         _getdevicedir
        .import         getdevicedir_has_no_DOS_3_3_implementation

_getdevicedir   := getdevicedir_has_no_DOS_3_3_implementation
