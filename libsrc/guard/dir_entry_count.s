;
; Scott Babcock, 2026-11-20
;
; A link-time guard for dir_entry_count(), in place of cc65's ProDOS version,
; which reads the ProDOS DIR, not DOS 3.3's, and would return a wrong count. A
; program that calls dir_entry_count() fails to link instead, naming the
; symbol below. For details, see section 4.2 of DESIGN.
;

        .export         _dir_entry_count
        .import         dir_entry_count_has_no_DOS_3_3_implementation

_dir_entry_count := dir_entry_count_has_no_DOS_3_3_implementation
