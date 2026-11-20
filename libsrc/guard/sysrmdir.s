;
; Scott Babcock, 2026-11-20
;
; unsigned char __fastcall__ _sysrmdir (const char* name);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's module of the same
; name, which makes _sysrmdir an alias of _sysremove. ProDOS's DESTROY
; removes files and directories alike, but with a2lib's _sysremove,
; rmdir would delete the file it names; DOS 3.3 has no directories. A
; program that calls rmdir fails to link instead, naming the symbol below.
;

        .export         __sysrmdir
        .import         rmdir_has_no_DOS_3_3_implementation

__sysrmdir      := rmdir_has_no_DOS_3_3_implementation
