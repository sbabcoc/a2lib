;
; Scott Babcock, 2026-11-20
;
; A link-time guard for mkdir(), in place of cc65's ProDOS version, which
; fails at run time under DOS 3.3, which has no directories. A program that
; calls mkdir() fails to link instead, naming the symbol below. For details,
; see section 4.2 of DESIGN.
;

        .export         __sysmkdir
        .import         mkdir_has_no_DOS_3_3_implementation

__sysmkdir      := mkdir_has_no_DOS_3_3_implementation
