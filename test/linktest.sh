#!/bin/bash
#
# Link-time guards (DESIGN.md 4.2): a program calling a function with no
# DOS 3.3 implementation, or one whose implementation is in an add-on it
# isn't linked with, must fail to link, and ld65 must name that function's
# guard symbol. Control programs, calling functions that do have one, must
# link. Then the add-ons (DESIGN.md 2): a program reaching an add-on only
# through stock modules must get the add-on's modules; a display library
# without its selector, or two display libraries, must fail to link; and
# test/selcheck.py checks each selector pulls in what it must.
#
#   bash test/linktest.sh lib
#
# CL65, OD65, AR65 and PYTHON name cl65, od65, ar65 and python3, if not on
# PATH.

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

# link NAME EXPECT BODY [ADDONS [stock]]: build a program whose main is
# BODY, linked with ADDONS (selectors and libraries) ahead of the core, and
# compiled with a2lib's headers, or cc65's alone with "stock". EXPECT is the
# guard symbol ld65 must name, or "-" when the program must link.
link () {
    local name=$1 expect=$2 body=$3 addons=${4:-} inc=(-I "$INC")
    [[ ${5:-} == stock ]] && inc=(-DSTOCK)
    cat > "$TMP/$name.c" <<EOF
#include <device.h>
#include <dio.h>
#include <apple2.h>
#ifndef STOCK
#include <a2reflow.h>
#endif
#include <conio.h>
#include <dirent.h>
#include <stdio.h>
#include <sys/statvfs.h>
#include <time.h>
#include <unistd.h>
int main (void) { $body }
EOF
    local out
    # shellcheck disable=SC2086
    out=$("$CL65" -t apple2 -O "${inc[@]}" -m "$TMP/$name.map" -o "$TMP/$name" \
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

link dir_entry_count dir_entry_count_has_no_DOS_3_3_implementation \
    'return dir_entry_count (opendir ("."));'

# The directory functions with cc65's <dirent.h>, whose struct dirent isn't
# a2lib's (DESIGN.md 2)
for f in opendir readdir closedir rewinddir; do
    case $f in
        opendir) body='return opendir (".") != NULL;' ;;
        readdir) body='return readdir ((DIR*) 0) != NULL;' ;;
        closedir) body='return closedir ((DIR*) 0);' ;;
        rewinddir) body='rewinddir ((DIR*) 0); return 0;' ;;
    esac
    link "stock$f" "${f}_needs_a2lib_dirent_h" "$body" "" stock
done

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
    'FILE* f = fopen ("X", "r"); DIR* d = opendir (".");
     if (f) fclose (f);
     if (d) { readdir (d); rewinddir (d); closedir (d); }
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

# Add-ons reached only through other modules: copies of stock modules in
# the add-on (cputs -> cputc, cgets -> cgetc, cprintf -> vcprintf -> cputc,
# time -> clock_gettime), and the selector's (printf -> write -> COUT)
for d in vt soft70; do
    start=; [[ $d == soft70 ]] && start="--start-addr 0x4000"
    sel="$start $DIR/a2lib-$d.o $DIR/a2lib-$d.lib"
    link "${d}cputs" - 'cputs ("X"); return 0;' "$sel"
    for m in cputs.o cputc.o gotoxy.o; do
        uses "${d}cputs" "$DIR/a2lib-$d.lib" "$m"
    done
    link "${d}cgets" - 'char b[4]; return cgets (b, sizeof b) != 0;' "$sel"
    for m in cgets.o cgetc.o; do
        uses "${d}cgets" "$DIR/a2lib-$d.lib" "$m"
    done
    link "${d}cprintf" - 'return cprintf ("X");' "$sel"
    for m in vcprintf.o cputc.o; do
        uses "${d}cprintf" "$DIR/a2lib-$d.lib" "$m"
    done
    link "${d}printf" - 'return printf ("X");' "$sel"
    uses "${d}printf" "$DIR/a2lib-$d.lib" cout.o
    # Without its selector, the library fails to link (vt.s)
    link "${d}nosel" a2lib_display_needs_selector_object \
        'cputs ("X"); return 0;' "$start $DIR/a2lib-$d.lib"
done
link twodisplays a2lib_display_needs_selector_object 'cputs ("X"); return 0;' \
    "--start-addr 0x4000 $DIR/a2lib-vt.o $DIR/a2lib-soft70.o $DIR/a2lib-vt.lib
     $DIR/a2lib-soft70.lib"

link timercgets - 'char b[4]; return cgets (b, sizeof b) != 0;' "$TIMER"
for m in cgets.o cgetc.o; do
    uses timercgets "$DIR/a2lib-timer.lib" "$m"
done
link timertime - 'return time (NULL) != 0;' "$TIMER"
for m in time.o gettime.o; do
    uses timertime "$DIR/a2lib-timer.lib" "$m"
done
# The display library, listed first, takes the timer library's place
link vttimer - 'char b[4]; return cgets (b, sizeof b) != 0;' \
    "$DIR/a2lib-vt.o $DIR/a2lib-timer.o $DIR/a2lib-vt.lib $TIMER"
for m in cgets.o cgetc.o; do
    uses vttimer "$DIR/a2lib-vt.lib" "$m"
done

link reflow - 'reflow_on (0); return printf ("X");' \
    "$DIR/a2lib-reflow.o $DIR/a2lib-reflow.lib"
uses reflow "$DIR/a2lib-reflow.lib" cout.o
link vtreflow - 'reflow_on (0); return printf ("X");' \
    "$DIR/a2lib-vt.o $DIR/a2lib-reflow.o $DIR/a2lib-vt.lib
     $DIR/a2lib-reflow.lib"
for m in cout.o viewport.o wherex.o; do
    uses vtreflow "$DIR/a2lib-vt.lib" "$m"
done
uses vtreflow "$DIR/a2lib-reflow.lib" reflow.o

"${PYTHON:-python3}" "$(dirname "$0")/selcheck.py" "$DIR" || fail=1

exit $fail
