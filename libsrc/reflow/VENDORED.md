# Modified cc65 modules

Modified copies of cc65 modules in `lib/a2lib-reflow.lib`, each with a
note in its header explaining the change:

- `cout.s` (from `libsrc/apple2/cout.s`): `COUT` is a vector, so the
  reflow filter can be switched in; the stock routine is `a2_rawcout`.

Because it replaces a stock module, compare it with cc65's version after
updating cc65.
