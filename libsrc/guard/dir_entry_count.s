;
; Scott Babcock, 2026-11-20
;
; unsigned int __fastcall__ dir_entry_count (DIR* dir);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which reads the ProDOS DIR, not DOS 3.3's, and would return a
; wrong count. A program that calls dir_entry_count fails to link
; instead, naming the symbol below.
;

        .export         _dir_entry_count
        .import         dir_entry_count_has_no_DOS_3_3_implementation

_dir_entry_count := dir_entry_count_has_no_DOS_3_3_implementation
