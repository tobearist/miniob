#!/bin/bash
set -euo pipefail
TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOPDIR"
DATA=/tmp/alter_dbg
rm -rf "$DATA"
mkdir -p "$DATA"
SOCK="$DATA/s.sock"
OBSERVER="${TOPDIR}/build_debug/bin/observer"
[[ -x "$OBSERVER" ]] || OBSERVER="${TOPDIR}/build/bin/observer"

"$OBSERVER" -f etc/observer.ini -s "$SOCK" >"$DATA/obs.log" 2>&1 &
PID=$!
sleep 2
run() { python3 scripts/miniob_sql_client.py -s "$SOCK" -t 10 "$1"; }

echo "=== create ==="
run "CREATE TABLE t(id int, v int);"
echo "=== insert ==="
run "INSERT INTO t VALUES(1, 10);"
echo "=== alter ==="
run "ALTER TABLE t ADD COLUMN c int;" || true
echo "=== select ==="
run "SELECT * FROM t;" || true
kill "$PID" 2>/dev/null || true
echo "=== observer log tail ==="
tail -80 "$DATA/obs.log"
