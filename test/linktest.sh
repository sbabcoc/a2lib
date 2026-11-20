#!/bin/bash
#
# Link-time guards (DESIGN.md 4.2): a program calling a function with no
# DOS 3.3 implementation must fail to link, and ld65 must name that
# function's guard symbol. A control program, calling functions that do
# have one, must link.
#
#   bash test/linktest.sh lib/apple2-dos33.lib
#
# CL65 names cl65, if not on PATH.

set -u

LIB=${1:?usage: linktest.sh path/to/apple2-dos33.lib}
CL65=${CL65:-cl65}
[[ -f "$LIB" ]] || { echo "linktest: no library at $LIB" >&2; exit 2; }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

fail=0

# link NAME EXPECT BODY: build a program whose main is BODY. EXPECT is the
# guard symbol ld65 must name, or "-" when the program must link.
link () {
    local name=$1 expect=$2 body=$3
    cat > "$TMP/$name.c" <<EOF
#include <device.h>
#include <dio.h>
#include <apple2.h>
#include <stdio.h>
#include <sys/statvfs.h>
#include <time.h>
#include <unistd.h>
int main (void) { $body }
EOF
    local out
    out=$("$CL65" -t apple2 -O -o "$TMP/$name" "$TMP/$name.c" "$LIB" 2>&1)
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

# Control: functions with DOS 3.3 versions, including remove(), which
# shares _sysremove with the stock rmdir
link control - \
    'struct timespec t; FILE* f = fopen ("X", "r"); if (f) fclose (f);
     remove ("X"); rename ("X", "Y"); chdir ("/6/1");
     return clock_gettime (CLOCK_REALTIME, &t);'

exit $fail
