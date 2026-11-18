#!/usr/bin/env bash
#
# Run a2lib's test programs on ReplicApple2Plus, headless (DESIGN.md 8).
#
#   test/emutest.sh [name...]       (or: make emutest MASTER=...)
#
# Builds DOS 3.3 disks holding the test programs (build/test/*), then runs
# each program with ReplicApple2Plus's headless runner, booting the DOS 3.3
# System Master in drive 1 with its test disk in drive 2, with and without
# the VideoTerm as each test needs. Each run's screen is kept in build/emu/
# and checked for its summary line. With names (for example "vttest" or
# "vttest-vt"), only those runs.
#
# The network run (nettest) adds the Uthernet II in slot 3 and runs in real
# time against an echo server on the host, which the card reaches through
# its gateway, 10.0.2.2. It needs nettest built (make test IP65=...),
# UTHERNET2, and python3 for the server; without the first two it's
# skipped, unless named.
#
# Environment:
#   MASTER    the DOS 3.3 System Master (DSK or WOZ); required
#   RUNNER    the runner's launcher (default: replicapple2plus-run on PATH)
#   AC        AppleCommander's command-line tool (default: ac)
#   ROMS      a ROM folder for the runner (default: the runner's own choice)
#   UTHERNET2 the folder holding the Uthernet2 plug-in jar, for nettest
#   SNAP      a folder to save a picture of each run's last screen in, as
#             <run>.png, as ReplicApple2Plus's main window shows it (the
#             runner's --snap: ReplicApple2Plus 1.11.0 or later)
#   MONITOR   the monitor those pictures show: color, white, green or amber
#             (default green, as hi-res text is drawn for)
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
NET_DISK="$OUT/a2libnet.dsk"

die() { echo "emutest: $*" >&2; exit 1; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
[[ -n "${MASTER:-}" ]] || die "set MASTER to the DOS 3.3 System Master (DSK or WOZ)"
[[ -f "$MASTER" ]] || die "MASTER not found: $MASTER"
command -v "$RUNNER" >/dev/null || die "runner not found: $RUNNER (set RUNNER)"
command -v "$AC" >/dev/null || die "AppleCommander not found: $AC (set AC)"

# The runs: name | program | card (vt for the VideoTerm, net for the
# Uthernet II, or -) | script | --until text | text that marks a pass. The
# script is --type/--expect/--wait steps after BRUN; @PORT@ in it is the
# echo server's port. Programs that end with "PRESS A KEY" wait there; the
# others end with their summary, and a failing one runs to the timeout.
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
nettest|nettest|net|--expect|SERVER PORT|--type|@PORT@\r|PRESS A KEY|ALL [0-9]* PASSED
'

# Answers one connection: reads a line to its CR, waits two seconds (the
# delay nettest times), and sends the line back. Its port goes to the file
# named first.
ECHO_SERVER='
import socket, sys, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(1)
with open(sys.argv[1], "w") as f:
    f.write(str(s.getsockname()[1]))
s.settimeout(600)
c, _ = s.accept()
data = b""
while not data.endswith(b"\r"):
    chunk = c.recv(64)
    if not chunk:
        break
    data += chunk
time.sleep(2)
c.sendall(data)
c.close()
'

names="$(printf '%s\n' "$RUNS" | cut -d'|' -f1)"
for w in "$@"; do
    printf '%s\n' "$names" | grep -qx -- "$w" || die "no run named $w (runs: $(echo $names))"
done

# The network run takes what the others don't: drop it if that's missing,
# or stop if it was asked for by name
net_missing=
[[ -f build/test/nettest ]] || net_missing="nettest isn't built (make test IP65=...)"
[[ -z "$net_missing" && -z "${UTHERNET2:-}" ]] && net_missing="UTHERNET2 isn't set"
[[ -z "$net_missing" && ! -d "$UTHERNET2" ]] && net_missing="UTHERNET2 isn't a folder: $UTHERNET2"
[[ -z "$net_missing" ]] && ! command -v python3 >/dev/null && net_missing="python3 isn't on PATH"
if [[ -n "$net_missing" ]]; then
    for w in "$@"; do
        [[ "$w" == nettest ]] && die "nettest: $net_missing"
    done
    (( $# == 0 )) && echo "SKIP nettest      $net_missing"
    RUNS="$(printf '%s\n' "$RUNS" | grep -v '^nettest|')"
fi

mkdir -p "$OUT"
[[ -n "${SNAP:-}" ]] && { mkdir -p "$SNAP" || die "couldn't create SNAP folder: $SNAP"; }
printf '[3]\ntype=uthernet2\n\n[6]\ntype=disk2\n' > "$OUT/net.ini"

# The test disks: the programs the runs use, as DOS 3.3 binary files. The
# network run's program has a disk of its own, since with it the programs
# would overflow one 140K disk.
make_disk() {
    local disk="$1" prog
    shift
    rm -f "$disk"
    "$AC" -dos140 "$disk" >/dev/null || die "couldn't create $disk"
    for prog in "$@"; do
        [[ -f "build/test/$prog" ]] || die "build/test/$prog missing (make test first)"
        "$AC" -as "$disk" "$(upper "$prog")" < "build/test/$prog" >/dev/null \
            || die "couldn't put $prog on $disk"
    done
}
make_disk "$DISK" $(printf '%s\n' "$RUNS" | grep -v '^[^|]*|[^|]*|net|' | cut -d'|' -f2 | sort -u)
printf '%s\n' "$RUNS" | grep -q '^[^|]*|[^|]*|net|' \
    && make_disk "$NET_DISK" $(printf '%s\n' "$RUNS" | grep '^[^|]*|[^|]*|net|' | cut -d'|' -f2 | sort -u)

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
    timeout=300
    server=
    if [[ "$vt" == net ]]; then
        # real time: the server's delay is real, and IP65's timeouts are counted
        args=("${args[@]/#$DISK/$NET_DISK}")
        args+=(--config "$OUT/net.ini" --plugins "$UTHERNET2" --real-time)
        timeout=60
        rm -f "$OUT/port"
        python3 -c "$ECHO_SERVER" "$OUT/port" &
        server=$!
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            [[ -s "$OUT/port" ]] && break
            sleep 0.5
        done
        [[ -s "$OUT/port" ]] || die "the echo server didn't start"
        script=("${script[@]//@PORT@/$(cat "$OUT/port")}")
    fi
    snap=()
    [[ -n "${SNAP:-}" ]] && snap=(--expect "$until_text" --snap "$SNAP/$name.png" --monitor "${MONITOR:-green}")
    args+=(${script[@]+"${script[@]}"} ${snap[@]+"${snap[@]}"} --until "$until_text" --timeout "$timeout" \
        --screen "$OUT/$name.txt")

    "$RUNNER" "${args[@]}" >/dev/null 2>"$OUT/$name.err"
    status=$?
    if [[ -n "$server" ]]; then
        kill "$server" 2>/dev/null
        wait "$server" 2>/dev/null
    fi
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
