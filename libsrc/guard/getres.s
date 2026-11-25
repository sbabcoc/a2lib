;
; Scott Babcock, 2026-11-20
;
; A link-time guard for clock_getres(), in place of cc65's ProDOS version,
; which fails with ENOSYS under DOS 3.3. A program that calls clock_getres
; fails to link instead, naming the symbol below, until the software clock has
; a clock_getres() of its own. For details, see section 4.2 of DESIGN.
;

        .export         _clock_getres
        .import         clock_getres_has_no_DOS_3_3_implementation

_clock_getres   := clock_getres_has_no_DOS_3_3_implementation
