#!/bin/bash
#
# Link-time guards (DESIGN.md 4.2): a program calling a function with no
# DOS 3.3 implementation, or one whose implementation is in an add-on it
# isn't linked with, must fail to link, and ld65 must name that function's
# guard symbol. Control programs, calling functions that do have one, must
# link. Then the add-ons' selectors (DESIGN.md 2): test/selcheck.py checks
# each pulls in what it must, and a program reaching an add-on only
# through stock modules must get the add-on's modules.
#
#   bash test/linktest.sh lib
#
# CL65, OD65 and AR65 name cl65, od65 and ar65, if not on PATH.

set -u

DIR=${1:?usage: linktest.sh LIBDIR}
CL65=${CL65:-cl65}
LIB=$DIR/a2lib-dos33.lib
[[ -f "$LIB" ]] || { echo "linktest: no library at $LIB" >&2; exit 2; }
INC=$(dirname "$0")/../include
TIMER="$DIR/a2lib-timer.o $DIR/a2lib-timer.lib"

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

fail=0

# link NAME EXPECT BODY [ADDONS]: build a program whose main is BODY,
# linked with ADDONS (selectors and libraries) ahead of the core. EXPECT is
# the guard symbol ld65 must name, or "-" when the program must link.
link () {
    local name=$1 expect=$2 body=$3 addons=${4:-}
    cat > "$TMP/$name.c" <<EOF
#include <device.h>
#include <dio.h>
#include <apple2.h>
#include <a2reflow.h>
#include <conio.h>
#include <stdio.h>
#include <sys/statvfs.h>
#include <time.h>
#include <unistd.h>
int main (void) { $body }
EOF
    local out
    # shellcheck disable=SC2086
    out=$("$CL65" -t apple2 -O -I "$INC" -m "$TMP/$name.map" -o "$TMP/$name" \
        "$TMP/$name.c" $addons "$LIB" 2>&1)
    local status=$?
    if [[ $expect == - ]]; then
        if (( status == 0 )); then
            echo "ok    $name links"
        else
            echo "FAIL  $name: expected to link"; echo "$out"; fail=1
        fi
    elif (( status != 0 )) && grep -q "$expect" <<< "$out"; then
        echo "ok    $name: $expect"
    else
        echo "FAIL  $name: expected a link error naming $expect"; echo "$out"; fail=1
    fi
}

link getcurrentdevice getcurrentdevice_has_no_DOS_3_3_implementation \
    'return getcurrentdevice ();'
link getdevicedir getdevicedir_has_no_DOS_3_3_implementation \
    'char buf[64]; return getdevicedir (1, buf, sizeof buf) != NULL;'
link getfirstdevice getfirstdevice_has_no_DOS_3_3_implementation \
    'return getfirstdevice ();'
link getnextdevice getnextdevice_has_no_DOS_3_3_implementation \
    'return getnextdevice (0);'
link dio_open dio_open_has_no_DOS_3_3_implementation \
    'return dio_open (0) != NULL;'
link dio_close dio_close_has_no_DOS_3_3_implementation \
    'return dio_close (NULL);'
link dio_read dio_read_has_no_DOS_3_3_implementation \
    'return dio_read (NULL, 0, NULL);'
link dio_write dio_write_has_no_DOS_3_3_implementation \
    'return dio_write (NULL, 0, NULL);'
link dio_query_sectcount dio_query_sectcount_has_no_DOS_3_3_implementation \
    'return dio_query_sectcount (NULL);'
link dio_query_sectsize dio_query_sectsize_has_no_DOS_3_3_implementation \
    'return dio_query_sectsize (NULL);'
link file_set_type file_set_type_has_no_DOS_3_3_implementation \
    'return file_set_type ("X", 6);'
link file_set_auxtype file_set_auxtype_has_no_DOS_3_3_implementation \
    'return file_set_auxtype ("X", 0);'
link statvfs statvfs_has_no_DOS_3_3_implementation \
    'struct statvfs s; return statvfs ("X", &s);'
link mkdir mkdir_has_no_DOS_3_3_implementation \
    'return mkdir ("X");'
link rmdir rmdir_has_no_DOS_3_3_implementation \
    'return rmdir ("X");'
link clock_getres clock_getres_has_no_DOS_3_3_implementation \
    'struct timespec t; return clock_getres (CLOCK_REALTIME, &t);'

# The software clock is in a2lib-timer.lib
link clock_gettime clock_gettime_needs_a2lib_timer \
    'struct timespec t; return clock_gettime (CLOCK_REALTIME, &t);'
link clock_settime clock_settime_needs_a2lib_timer \
    'struct timespec t = {0, 0}; return clock_settime (CLOCK_REALTIME, &t);'
link time clock_gettime_needs_a2lib_timer \
    'return time (NULL) != 0;'

# Controls: functions with DOS 3.3 versions, including remove(), which
# shares _sysremove with the stock rmdir; and the clock, with the timer
link control - \
    'FILE* f = fopen ("X", "r"); if (f) fclose (f);
     remove ("X"); rename ("X", "Y"); return chdir ("/6/1");'
link clock - \
    'struct timespec t = {0, 0}; clock_settime (CLOCK_REALTIME, &t);
     clock_gettime (CLOCK_REALTIME, &t); return time (NULL) != 0;' "$TIMER"

# uses NAME LIB MODULE: NAME's map shows MODULE linked from LIB
uses () {
    if grep -qF "$2($3)" "$TMP/$1.map"; then
        echo "ok    $1: $3 from $(basename "$2")"
    else
        echo "FAIL  $1: $3 not from $(basename "$2")"; fail=1
    fi
}

# Selectors: replacements reached only through other modules (cputs ->
# cputc, cgets -> cgetc, printf -> write -> COUT, time -> clock_gettime)
for d in vt c40win soft70; do
    start=; [[ $d == soft70 ]] && start="--start-addr 0x4000"
    link "sel$d" - 'char b[4]; cputs ("X"); cgets (b, sizeof b);
     return printf ("X");' "$start $DIR/a2lib-$d.o $DIR/a2lib-$d.lib"
    for m in cputc.o cgetc.o gotoxy.o wherex.o cout.o; do
        uses "sel$d" "$DIR/a2lib-$d.lib" "$m"
    done
done
link seltimer - 'char b[4]; cgets (b, sizeof b); return time (NULL) != 0;' \
    "$TIMER"
uses seltimer "$DIR/a2lib-timer.lib" cgetc.o
uses seltimer "$DIR/a2lib-timer.lib" gettime.o
link selreflow - 'reflow_on (0); return printf ("X");' \
    "$DIR/a2lib-reflow.o $DIR/a2lib-reflow.lib"
uses selreflow "$DIR/a2lib-reflow.lib" cout.o
link selvtreflow - 'reflow_on (0); return printf ("X");' \
    "$DIR/a2lib-vt.o $DIR/a2lib-reflow.o $DIR/a2lib-vt.lib
     $DIR/a2lib-reflow.lib"
uses selvtreflow "$DIR/a2lib-vt.lib" cout.o
uses selvtreflow "$DIR/a2lib-vt.lib" viewport.o
uses selvtreflow "$DIR/a2lib-reflow.lib" reflow.o

python3 "$(dirname "$0")/selcheck.py" "$DIR" || fail=1

exit $fail
