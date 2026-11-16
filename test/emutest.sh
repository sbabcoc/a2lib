#!/usr/bin/env bash
#
# Run a2lib's test programs on ReplicApple2Plus, headless (DESIGN.md 8).
#
#   test/emutest.sh [name...]       (or: make emutest MASTER=...)
#
# Builds a DOS 3.3 disk holding the test programs (build/test/*), then runs
# each program with ReplicApple2Plus's headless runner, booting the DOS 3.3
# System Master in drive 1 with the test disk in drive 2, with and without
# the VideoTerm as each test needs. Each run's screen is kept in build/emu/
# and checked for its summary line. With names (for example "vttest" or
# "vttest-vt"), only those runs.
#
# Environment:
#   MASTER   the DOS 3.3 System Master (DSK or WOZ); required
#   RUNNER   the runner's launcher (default: replicapple2plus-run on PATH)
#   AC       AppleCommander's command-line tool (default: ac)
#   ROMS     a ROM folder for the runner (default: the runner's own choice)
#
# Exit status: 0 if every run passed, 1 otherwise. Runs in bash 3.2 (macOS)
# and later.
#
# Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.

set -uo pipefail

RUNNER="${RUNNER:-replicapple2plus-run}"
AC="${AC:-ac}"
OUT=build/emu
DISK="$OUT/a2libtests.dsk"

die() { echo "emutest: $*" >&2; exit 1; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
[[ -n "${MASTER:-}" ]] || die "set MASTER to the DOS 3.3 System Master (DSK or WOZ)"
[[ -f "$MASTER" ]] || die "MASTER not found: $MASTER"
command -v "$RUNNER" >/dev/null || die "runner not found: $RUNNER (set RUNNER)"
command -v "$AC" >/dev/null || die "AppleCommander not found: $AC (set AC)"

# The runs: name | program | VideoTerm (vt or -) | script | --until text |
# text that marks a pass. The script is --type/--expect/--wait steps after
# BRUN. Programs that end with "PRESS A KEY" wait there; the others end
# with their summary, and a failing one runs to the timeout.
RUNS='
filetest|filetest|-||PASSED|ALL [0-9]* PASSED
timertest|timertest|-|--expect|TYPE A WORD|--wait|0.2|--type|HELLO\r|PASSED|ALL [0-9]* PASSED
vttest|vttest|-||PRESS A KEY|ALL [0-9]* PASSED
vttest-vt|vttest|vt||PRESS A KEY|ALL [0-9]* PASSED
wintest|wintest|-||PRESS A KEY|ALL [0-9]* PASSED
wintest-vt|wintest|vt||PRESS A KEY|ALL [0-9]* PASSED
s70test|s70test|-||PRESS A KEY|ALL [0-9]* PASSED
s70test-vt|s70test|vt||PRESS A KEY|ALL [0-9]* PASSED
reflowtest|reflowtest|-||PRESS A KEY|ALL [0-9]* PASSED
reflowvt-vt|reflowvt|vt||PRESS A KEY|ALL [0-9]* PASSED
reflowwin|reflowwin|-||PRESS A KEY|ALL [0-9]* PASSED
reflows70|reflows70|-||PRESS A KEY|ALL [0-9]* PASSED
cswtest-vt|cswtest|vt|--expect|TYPE A WORD|--type|HELLO\r|PRESS A KEY|^0 FAILED
cswwtest|cswwtest|-|--expect|TYPE A WORD|--type|HELLO\r|PRESS A KEY|^0 FAILED
cswstest|cswstest|-|--expect|TYPE A WORD|--type|HELLO\r|PRESS A KEY|^0 FAILED
'

names="$(printf '%s\n' "$RUNS" | cut -d'|' -f1)"
for w in "$@"; do
    printf '%s\n' "$names" | grep -qx -- "$w" || die "no run named $w (runs: $(echo $names))"
done

mkdir -p "$OUT"

# The test disk: every program the runs use, as DOS 3.3 binary files
rm -f "$DISK"
"$AC" -dos140 "$DISK" >/dev/null || die "couldn't create $DISK"
for prog in $(printf '%s\n' "$RUNS" | cut -d'|' -f2 | sort -u); do
    [[ -n "$prog" ]] || continue
    [[ -f "build/test/$prog" ]] || die "build/test/$prog missing (make test first)"
    "$AC" -as "$DISK" "$(upper "$prog")" < "build/test/$prog" >/dev/null \
        || die "couldn't put $prog on $DISK"
done

failed=0
ran=0
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS='|' read -r -a f <<< "$line"
    name="${f[0]}" prog="${f[1]}" vt="${f[2]}"
    n=${#f[@]}
    until_text="${f[n-2]}" pass_re="${f[n-1]}"
    script=("${f[@]:3:n-5}")
    [[ ${#script[@]} -eq 1 && -z "${script[0]}" ]] && script=()

    if (( $# > 0 )); then
        wanted=0
        for w in "$@"; do [[ "$w" == "$name" ]] && wanted=1; done
        (( wanted )) || continue
    fi

    args=(--d1 "$MASTER" --d2 "$DISK" --type "BRUN $(upper "$prog"),D2\\r")
    [[ -n "${ROMS:-}" ]] && args=(--roms "$ROMS" "${args[@]}")
    [[ "$vt" == vt ]] && args+=(--videoterm)
    args+=(${script[@]+"${script[@]}"} --until "$until_text" --timeout 300 --screen "$OUT/$name.txt")

    "$RUNNER" "${args[@]}" >/dev/null 2>"$OUT/$name.err"
    status=$?
    ran=$((ran + 1))
    summary="$(grep -E -m1 "ALL [0-9]+ PASSED|[0-9]+ OF [0-9]+ FAILED|^[0-9]+ FAILED" "$OUT/$name.txt" 2>/dev/null)"
    if (( status == 0 )) && grep -q -E "$pass_re" "$OUT/$name.txt"; then
        printf 'PASS %-12s %s\n' "$name" "$summary"
    else
        case $status in
            0) why="${summary:-no summary}" ;;
            2) why="didn't boot" ;;
            3) why="timed out${summary:+: $summary}" ;;
            4) why="machine stopped" ;;
            *) why="runner status $status: $(head -1 "$OUT/$name.err")" ;;
        esac
        printf 'FAIL %-12s %s (screen: %s)\n' "$name" "$why" "$OUT/$name.txt"
        failed=$((failed + 1))
    fi
done <<< "$RUNS"

if (( failed == 0 )); then
    echo "ALL $ran RUNS PASSED"
else
    echo "$failed OF $ran RUNS FAILED"
fi
(( failed == 0 ))
