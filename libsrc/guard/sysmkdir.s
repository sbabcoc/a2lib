;
; Scott Babcock, 2026-11-20
;
; unsigned char _sysmkdir (const char* name, ...);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3, which has no
; directories. A program that calls mkdir fails to link instead, naming
; the symbol below.
;

        .export         __sysmkdir
        .import         mkdir_has_no_DOS_3_3_implementation

__sysmkdir      := mkdir_has_no_DOS_3_3_implementation
