;
; Scott Babcock, 2026-11-20
;
; int __fastcall__ statvfs(const char *pathname, struct statvfs *statvfsbuf);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails at run time under DOS 3.3. A program that calls
; statvfs fails to link instead, naming the symbol below.
;

        .export         _statvfs
        .import         statvfs_has_no_DOS_3_3_implementation

_statvfs        := statvfs_has_no_DOS_3_3_implementation
