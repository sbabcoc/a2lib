# Modified cc65 modules

Modified copies of cc65 modules in `lib/a2lib-timer.lib`, each with a
note in its header explaining the change:

- `cgetc.s`, `kbhit.s` (from `libsrc/apple2/`): the wait loop calls the
  cooperative timer's tick hook; `kbhit` waits one tick while the timer
  is in use. The display libraries include this `kbhit.s` too.

`gettime.s` and `settime.s` replace stock modules of the same name (and
the guards in `lib/a2lib-dos33.lib`, DESIGN.md 4.2) with a software clock
of a2lib's own (DESIGN.md 6.3).

Because these replace stock modules, compare them with cc65's versions
after updating cc65.
