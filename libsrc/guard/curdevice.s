;
; Scott Babcock, 2026-11-20
;
; unsigned char getcurrentdevice (void);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; getcurrentdevice fails to link instead, naming the symbol below.
;

        .export         _getcurrentdevice
        .import         getcurrentdevice_has_no_DOS_3_3_implementation

_getcurrentdevice := getcurrentdevice_has_no_DOS_3_3_implementation
