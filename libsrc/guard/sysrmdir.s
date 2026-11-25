;
; Scott Babcock, 2026-11-20
;
; A link-time guard for rmdir(), in place of cc65's version, which makes
; _sysrmdir an alias of _sysremove. ProDOS's DESTROY removes files and
; directories alike, but with a2lib's _sysremove, rmdir() would delete the
; file it names; DOS 3.3 has no directories. A program that calls rmdir()
; fails to link instead, naming the symbol below. For details, see section 4.2
; of DESIGN.
;

        .export         __sysrmdir
        .import         rmdir_has_no_DOS_3_3_implementation

__sysrmdir      := rmdir_has_no_DOS_3_3_implementation
