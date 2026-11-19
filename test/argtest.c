/*
** The program exectest execs (DESIGN.md 5.10): checks the arguments
** exec() passed through page 2, and that mainargs cleared their marker.
**
** Started by exectest, it expects argv[1] "PRE=4/4" (exectest's own
** checks), then ONE, TWO 2 (quoted), THREE and 100 X's, and ends with the
** summary. Started from the keyboard (BRUN ARGTEST,D2) it must get no
** arguments, and prints DIRECT OK.
**
** Built with apple2-dos33.lib. Run under DOS 3.3 with the test disk in
** drive 2, by exectest.
*/

#include <stdio.h>
#include <string.h>

#define PAGE2   ((unsigned char*) 0x0200)

static unsigned char passed, total;

static void check (const char* what, int ok)
{
    ++total;
    if (ok) {
        ++passed;
    }
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
}

static int all_x (const char* s)
{
    unsigned char n = 0;

    while (*s == 'X') {
        ++s;
        ++n;
    }
    return *s == '\0' && n == 100;
}

/* The byte after the first CR in page 2: exec()'s marker, until cleared */
static unsigned char after_cr (void)
{
    unsigned char i = 0;

    while (PAGE2[i] != 0x8D && ++i) {
    }
    return PAGE2[(unsigned char) (i + 1)];
}

int main (int argc, char* argv[])
{
    if (argc == 1) {
        printf ("DIRECT %s\n", argv[0][0] == '\0' ? "OK" : "ARGV[0] NOT EMPTY");
        return 0;
    }

    printf ("A2LIB EXEC ARGUMENTS\n");
    check ("ARGC 6", argc == 6);
    check ("ARGV[0] EMPTY", argv[0][0] == '\0');
    if (argc == 6) {
        check ("PRE-EXEC CHECKS", strcmp (argv[1], "PRE=4/4") == 0);
        check ("ONE", strcmp (argv[2], "ONE") == 0);
        check ("QUOTED TWO 2", strcmp (argv[3], "TWO 2") == 0);
        check ("THREE", strcmp (argv[4], "THREE") == 0);
        check ("100 X'S", all_x (argv[5]));
    }
    check ("MARKER CLEARED", after_cr () != 0x00);

    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    return 0;
}
