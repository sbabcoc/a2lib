;
; Scott Babcock, 2026-11-20
;
; A link-time guard for statvfs(), in place of cc65's ProDOS version, which
; fails at run time under DOS 3.3. A program that calls statvfs() fails to
; link instead, naming the symbol below. For details, see section 4.2 of
; DESIGN.
;

        .export         _statvfs
        .import         statvfs_has_no_DOS_3_3_implementation

_statvfs        := statvfs_has_no_DOS_3_3_implementation
