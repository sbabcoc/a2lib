;
; Cooperative timer for the cc65 apple2 target (DESIGN.md 6.3)
;

; Tick length. A tick is one increment of RNDH by a 15-cycle wait loop:
; 3,844 cycles, plus the time spent in the tick routine itself (TICK_CYC,
; counted for its common path). At the II+'s average CPU clock of
; 1,020,484 Hz (NTSC), a tick is TICK_MS + TICK_NUM / TICK_DEN ms. The
; Bresenham-style error term in a2_tick distributes the fraction.
TICK_MS         = 3
TICK_NUM        = 160           ; 3,934.6 cycles = 3.855602 ms (DESIGN.md 6.3)
TICK_DEN        = 187
TICK_MSDEN      = TICK_MS * TICK_DEN + TICK_NUM ; ms per tick * TICK_DEN

; Ticks for a given number of milliseconds, rounded (for constants)
.define MS_TICKS(ms) ((ms) * TICK_DEN + TICK_MSDEN / 2) / TICK_MSDEN

NSLOT           = 4             ; Timer slots

; Slot flags
TF_ALLOC        = $80           ; Slot in use
TF_ACTIVE       = $40           ; Counting down
TF_PERIODIC     = $20           ; Restarts when it expires
TF_DUE          = $01           ; Expired, callback not yet run

KSWL            := $38          ; Input hook
DOS_KSW         := $AA55        ; 48K DOS 3.3: saved true input hook
DOS_KINT        := $9D02        ; 48K DOS 3.3: address of its keyboard intercept

        .global         a2_tickhook, a2_tickon
        .global         a2_tick, a2_timer_arm, a2_timer_restart
        .global         tmr_ticks, tmr_fn, tmr_per
        .global         t_ms, t_rem, t_sec, t_sec60
