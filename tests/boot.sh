#!/usr/bin/env bash
# Boot tests: type a scripted session into each image's serial port under
# QEMU, with a time limit, then compare the transcript with
# tests/expected/NAME.txt and QEMU's exit status with the expected one.
#
# Sessions are in tests/sessions/, one command per line; `\b`, `\x15`
# (Ctrl-U) and `\x03` (Ctrl-C) stand for the editing keys. In transcripts,
# control characters are shown as ^H, ^G, ... (cat -v) and the number
# printed by `ticks` as N, since it differs on every run.
#
# usage: tests/boot.sh [BUILD_DIR]      (default: build)
#        UPDATE=1 tests/boot.sh         rewrite tests/expected/ from this run
#                                       (read `git diff` before committing)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUILD="${1:-build}"
TIMEOUT="${BOOT_TIMEOUT:-60}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# session NAME ARCH SESSION-FILE STATUS
session() {
    local name=$1 arch=$2 script=$3 want=$4
    local image="$BUILD/shell-$arch.elf"
    # $(...) drops the file's final newline; put it back so the last
    # command is entered.
    printf '%b\n' "$(cat "$HERE/sessions/$script")" > "$TMP/$name.in"
    timeout "$TIMEOUT" "$ROOT/scripts/qemu.sh" "$arch" "$image" \
        < "$TMP/$name.in" > "$TMP/$name.raw" 2> "$TMP/$name.err"
    local status=$?
    tr -d '\r' < "$TMP/$name.raw" | cat -v \
        | sed -E 's/^ticks: [0-9]+ /ticks: N /' > "$TMP/$name.out"
    if [ "$status" -eq 124 ]; then
        echo "FAIL $name: QEMU did not exit within ${TIMEOUT}s"
        sed 's/^/    /' "$TMP/$name.out" | tail -20
        fail=$((fail + 1))
    elif [ "$status" -ne "$want" ]; then
        echo "FAIL $name: exit status $status, expected $want"
        sed 's/^/    /' "$TMP/$name.out" "$TMP/$name.err" | tail -20
        fail=$((fail + 1))
    elif [ "${UPDATE:-0}" = 1 ]; then
        cp "$TMP/$name.out" "$HERE/expected/$name.txt"
        echo "upd  $name (exit status $status)"
        pass=$((pass + 1))
    elif ! diff -u "$HERE/expected/$name.txt" "$TMP/$name.out" > "$TMP/$name.diff"; then
        echo "FAIL $name: transcript differs from tests/expected/$name.txt"
        sed 's/^/    /' "$TMP/$name.diff"
        fail=$((fail + 1))
    else
        echo "ok   $name (exit status $status)"
        pass=$((pass + 1))
    fi
}

session session-x86_64  x86_64  x86_64.txt  33
session panic-x86_64    x86_64  panic.txt   37
session session-aarch64 aarch64 aarch64.txt 0
session panic-aarch64   aarch64 panic.txt   2

echo "boot tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
