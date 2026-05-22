#!/bin/bash
# ALTER TABLE ADD COLUMN 功能测试
#
# 用法:
#   cd /root/miniob
#   chmod +x scripts/run_alter_table_test.sh
#   ./scripts/run_alter_table_test.sh

set -euo pipefail

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOPDIR"

fix_windows_crlf() {
  local f
  for f in build.sh scripts/*.sh; do
    if [[ -f "$f" ]]; then
      sed -i 's/\r$//' "$f" 2>/dev/null || sed -i '' 's/\r$//' "$f" 2>/dev/null || true
    fi
  done
}
fix_windows_crlf

resolve_build_bin_dir() {
  local d
  for d in "${TOPDIR}/build" "${TOPDIR}/build_debug" "${TOPDIR}/build_release"; do
    if [[ -x "${d}/bin/observer" ]]; then
      BUILD_DIR="$d"
      OBSERVER="${BUILD_DIR}/bin/observer"
      return 0
    fi
  done
  return 1
}

BUILD_DIR=""
OBSERVER=""
CONFIG="${TOPDIR}/etc/observer.ini"
DATA_DIR="/tmp/miniob_alter_table_test_$$"

pass=0
fail=0

log() { echo "[alter-table-test] $*"; }
die() { echo "[alter-table-test] ERROR: $*" >&2; exit 1; }

cleanup() {
  if [[ -n "${OBSERVER_PID:-}" ]] && kill -0 "$OBSERVER_PID" 2>/dev/null; then
    kill "$OBSERVER_PID" 2>/dev/null || true
    wait "$OBSERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

run_sql() {
  local sql="$1"
  python3 "${TOPDIR}/scripts/miniob_sql_client.py" -s "$SERVER_SOCK" -t 15 "$sql" 2>&1 || true
}

expect_success() {
  local name="$1"
  local sql="$2"
  local out
  out=$(run_sql "$sql")
  if echo "$out" | grep -qi "SUCCESS"; then
    log "PASS: $name"
    pass=$((pass + 1))
  else
    log "FAIL: $name"
    log "  SQL: $sql"
    log "  OUT: $out"
    fail=$((fail + 1))
  fi
}

expect_failure() {
  local name="$1"
  local sql="$2"
  local out
  out=$(run_sql "$sql")
  if echo "$out" | grep -qi "FAILURE"; then
    log "PASS: $name"
    pass=$((pass + 1))
  else
    log "FAIL: $name (expected FAILURE)"
    log "  SQL: $sql"
    log "  OUT: $out"
    fail=$((fail + 1))
  fi
}

expect_select_ok() {
  local name="$1"
  local sql="$2"
  local out
  out=$(run_sql "$sql")
  if echo "$out" | grep -qi "FAILURE"; then
    log "FAIL: $name"
    log "  SQL: $sql"
    log "  OUT: $out"
    fail=$((fail + 1))
  else
    log "PASS: $name"
    pass=$((pass + 1))
  fi
}

if [[ "${MINIOB_BUILD:-1}" == "1" ]]; then
  log "Building MiniOB..."
  bash ./build.sh debug --make -j"$(nproc 2>/dev/null || echo 4)" observer obclient
fi

if ! resolve_build_bin_dir; then
  die "observer not found. Run build first."
fi

mkdir -p "$DATA_DIR"
SERVER_SOCK="${DATA_DIR}/miniob.sock"

log "Starting observer..."
(
  cd "$DATA_DIR"
  "$OBSERVER" -f "$CONFIG" -s "$SERVER_SOCK" </dev/null >/dev/null 2>&1
) &
OBSERVER_PID=$!
sleep 3

if ! kill -0 "$OBSERVER_PID" 2>/dev/null; then
  die "observer failed to start"
fi

log "Running ALTER TABLE test cases..."

# 1. 空表加列
expect_success "create table" "CREATE TABLE Alter_t1(id int, name char(4));"
expect_success "add column empty" "ALTER TABLE Alter_t1 ADD COLUMN score int;"
expect_select_ok "desc after add" "DESC Alter_t1;"

# 2. 有数据表加列，旧行新列为 0
expect_success "create table 2" "CREATE TABLE Alter_t2(id int, val int);"
expect_success "insert t2" "INSERT INTO Alter_t2 VALUES(1, 100);"
expect_success "add column t2" "ALTER TABLE Alter_t2 ADD COLUMN extra int;"
expect_select_ok "select t2 after alter" "SELECT * FROM Alter_t2;"
expect_success "insert with new col" "INSERT INTO Alter_t2 VALUES(2, 200, 50);"
expect_select_ok "select t2 two rows" "SELECT * FROM Alter_t2;"

# 3. 重复列名
expect_failure "duplicate column" "ALTER TABLE Alter_t2 ADD COLUMN extra int;"

# 4. 表不存在
expect_failure "table not exist" "ALTER TABLE Alter_not_exist ADD COLUMN x int;"

# 5. 带索引表加列
expect_success "create table 3" "CREATE TABLE Alter_t3(id int, v int);"
expect_success "insert t3" "INSERT INTO Alter_t3 VALUES(1, 10);"
expect_success "create index" "CREATE INDEX idx_alter_t3 ON Alter_t3(id);"
expect_success "add column indexed" "ALTER TABLE Alter_t3 ADD COLUMN note char(4);"
expect_select_ok "select indexed after alter" "SELECT * FROM Alter_t3;"

# 6. 省略 COLUMN 关键字
expect_success "add without column kw" "ALTER TABLE Alter_t1 ADD flag int;"

# 7. DROP TABLE 回归（不破坏已有功能）
expect_success "drop for regression" "DROP TABLE Alter_t1;"

log "========================================"
log "Results: PASS=$pass FAIL=$fail"
if [[ "$fail" -eq 0 ]]; then
  log "All alter table tests passed."
  exit 0
else
  log "Some tests failed."
  exit 1
fi
