/*
** Probe for exec() under DOS 3.3 (DESIGN.md 5.10): what happens when DOS
** fails a command after the hand-off, once the C library has shut down?
**
** Mirrors exec()'s hand-off: errprobe_arm (errstub.s) copies a stub to
** page 3 and points crt0's `done` at it, and main returns, so the
** destructors run and _exit restores the zero page, as with
** exit_with_params. The stub reconnects DOS's intercepts ($3EA) and sends
** BRUN for a file that doesn't exist, so DOS's error handler ($A6D5) runs.
**
**   errprobe     The stub first undoes initprompt (CURLIN+1 = $FF,
**                PROMPT = ']') and clears ERRFLG, which this program sets
**                beforehand as if ONERR were active. Expected: DOS prints
**                FILE NOT FOUND and warmstarts BASIC, with no Applesoft
**                error " IN <line>", and BASIC answers at the prompt.
**   errproberaw  (-DRAW) No reset: DOS sees a "running" program and passes
**                the error to Applesoft's handler. A diagnostic: read its
**                screen (build/emu/errproberaw.txt).
**
** Links read.s on purpose (keep_read, below).
**
** Built with apple2-dos33.lib. Run under DOS 3.3 with the test disk in
** drive 2. emutest then types PRINT 6*7 at the prompt.
*/

#include <stdio.h>
#include <unistd.h>

void __fastcall__ errprobe_arm (unsigned char reset);

/* Links read.s, whose constructor (initprompt) sets PROMPT and CURLIN+1 so
** that DOS sees a running program, as in any program that reads stdin.
** Without it, nothing undoes the ] prompt state BRUN started in, and the
** two variants are indistinguishable. */
int (*const keep_read) (int, void*, unsigned) = read;

int main (void)
{
#ifdef RAW
    printf ("A2LIB ERROR PROBE (NO RESET)\n");
    errprobe_arm (0);
#else
    printf ("A2LIB ERROR PROBE (RESET)\n");
    *(unsigned char*) 0xD8 = 0x80;      /* ERRFLG, as if ONERR were set */
    errprobe_arm (1);
#endif
    return 0;                           /* To the stub, through done */
}
