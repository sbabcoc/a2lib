;
; Scott Babcock, 2026-11-20
;
; int __fastcall__ clock_getres (clockid_t clk_id, struct timespec *res);
;
; Link-time guard (DESIGN.md 4.2): replaces cc65's ProDOS module of the
; same name, which fails with ENOSYS under DOS 3.3. A program that calls
; clock_getres fails to link instead, naming the symbol below, until the
; software clock (gettime.s) gets a clock_getres of its own.
;

        .export         _clock_getres
        .import         clock_getres_has_no_DOS_3_3_implementation

_clock_getres   := clock_getres_has_no_DOS_3_3_implementation
