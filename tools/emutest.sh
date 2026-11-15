#!/bin/sh
# Runs the test programs on ReplicApple2Plus's headless runner and reports
# each result (make emutest). Each program is on its own disk,
# DISKS/<name>.dsk, BRUN from drive 2 after booting the DOS 3.3 System
# Master in drive 1. Each run's screen is kept in DISKS/<name>-<config>.txt.
#
#   usage: tools/emutest.sh DISKS
#   environment: EMU_RUN (the runner), EMU_ROMS (its ROM folder),
#                DOS33_MASTER (the boot disk), EMU_TIMEOUT (seconds per run)
set -u

DISKS=${1:?usage: tools/emutest.sh DISKS}
: "${EMU_RUN:?EMU_RUN must name replicapple2plus-run}"
: "${EMU_ROMS:?EMU_ROMS must name the ROM folder}"
: "${DOS33_MASTER:?DOS33_MASTER must name the DOS 3.3 System Master image}"
EMU_TIMEOUT=${EMU_TIMEOUT:-120}

[ -x "$EMU_RUN" ] || { echo "emutest: $EMU_RUN isn't there (./gradlew installDist in ReplicApple2Plus)" >&2; exit 1; }

passed=0
failed=0
failures=

# run NAME CONFIG INPUT
#   CONFIG: vt (VideoTerm in slot 3) or bare (no card)
#   INPUT:  input (the program asks for a word) or none
run() {
    name=$1 config=$2 input=$3
    upper=$(echo "$name" | tr a-z A-Z)
    screen="$DISKS/$name-$config.txt"
    set -- --roms "$EMU_ROMS" --d1 "$DOS33_MASTER" --d2 "$DISKS/$name.dsk" \
        --timeout "$EMU_TIMEOUT" --screen "$screen" --type "BRUN $upper,D2\\r"
    [ "$config" = vt ] && set -- "$@" --videoterm
    if [ "$input" = input ]; then
        set -- "$@" --expect "TYPE A WORD"
        # timertest counts the time spent waiting for the word: pause as a person would
        [ "$name" = timertest ] && set -- "$@" --wait 0.5
        set -- "$@" --type "HELLO\\r"
    fi
    case $name in
        # filetest and timertest return to BASIC after their summary
        filetest|timertest) set -- "$@" --until "PASSED" ;;
        *) set -- "$@" --until "PRESS A KEY" ;;
    esac
    "$EMU_RUN" "$@" 2>"$screen.err"
    status=$?
    case $name in
        csw*) pattern='^0 FAILED\.' ;;          # cswtest prints its failure count
        *) pattern='ALL [0-9]+ PASSED' ;;
    esac
    if [ $status -eq 0 ] && grep -Eq "$pattern" "$screen"; then
        passed=$((passed + 1))
        echo "PASS $name ($config): $(grep -Eo 'ALL [0-9]+ PASSED|^0 FAILED' "$screen" | head -n 1)"
    else
        failed=$((failed + 1))
        failures="$failures $name-$config"
        case $status in
            0) why="finished without a pass line" ;;
            2) why="didn't boot" ;;
            3) why="timed out" ;;
            4) why="the machine stopped" ;;
            *) why="runner error $status" ;;
        esac
        echo "FAIL $name ($config): $why -- see $screen"
        sed 's/^/    /' "$screen.err"
    fi
}

# The configurations each program's source comment names
run filetest  bare none
run timertest bare input
run vttest    vt   none
run vttest    bare none
run wintest   vt   none
run wintest   bare none
run s70test   vt   none
run s70test   bare none
run cswtest   vt   input
run cswwtest  bare input
run cswstest  bare input
run reflowtest bare none
run reflowvt  vt   none
run reflowvt  bare none
run reflowwin bare none
run reflows70 bare none

echo "emutest: $passed passed, $failed failed${failures:+:$failures}"
[ $failed -eq 0 ]
