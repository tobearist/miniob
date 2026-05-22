#!/bin/bash
# Drop Table 功能测试（任务五）
# 工程根目录: C:\Users\HUAWEI\Desktop\project2\miniob (Windows)
#              /root/miniob (Dev Container) 或 ECS/WSL 挂载路径
#
# 用法:
#   cd /root/miniob   # 或你的 miniob 根目录
#   chmod +x scripts/run_drop_table_test.sh
#   ./scripts/run_drop_table_test.sh
#
# 可选环境变量:
#   MINIOB_BUILD=0     跳过编译（已编译过时）
#   MINIOB_REPO=/path  源码根目录，默认脚本上级目录

set -euo pipefail

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOPDIR"

# Windows 检出时代码常为 CRLF，在 Linux 容器里会导致 build.sh 报错 $'\r'
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
CLIENT=""
CONFIG="${TOPDIR}/etc/observer.ini"
DATA_DIR="/tmp/miniob_drop_table_test_$$"

pass=0
fail=0

log() { echo "[drop-table-test] $*"; }
die() { echo "[drop-table-test] ERROR: $*" >&2; exit 1; }

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
  local out
  # obclient 是交互式程序，管道输入会卡住；用 Python 客户端（与 miniob_test 相同协议）
  out=$(python3 "${TOPDIR}/scripts/miniob_sql_client.py" -s "$SERVER_SOCK" -t 15 "$sql" 2>&1) || true
  echo "$out"
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

# SELECT 成功时返回表头/数据，不一定包含 SUCCESS 字样
expect_select_ok() {
  local name="$1"
  local sql="$2"
  local out
  out=$(run_sql "$sql")
  if echo "$out" | grep -qi "FAILURE"; then
    log "FAIL: $name (got FAILURE)"
    log "  SQL: $sql"
    log "  OUT: $out"
    fail=$((fail + 1))
  else
    log "PASS: $name"
    pass=$((pass + 1))
  fi
}

# --- build ---
if [[ "${MINIOB_BUILD:-1}" == "1" ]]; then
  log "Building MiniOB (observer + obclient only, skip unit tests)..."
  bash ./build.sh debug --make -j"$(nproc 2>/dev/null || echo 4)" observer obclient
fi

if ! resolve_build_bin_dir; then
  die "observer not found under build/, build_debug/ or build_release/. Run: bash build.sh debug --make -j4 observer"
fi
log "Using observer from ${BUILD_DIR}/bin"

mkdir -p "$DATA_DIR"
SERVER_SOCK="${DATA_DIR}/miniob.sock"

log "Starting observer (work dir: $DATA_DIR, socket: $SERVER_SOCK)..."
(
  cd "$DATA_DIR"
  "$OBSERVER" -f "$CONFIG" -s "$SERVER_SOCK" </dev/null >/dev/null 2>&1
) &
OBSERVER_PID=$!
sleep 3

if ! kill -0 "$OBSERVER_PID" 2>/dev/null; then
  die "observer failed to start"
fi

log "Running Drop Table test cases..."

# 1. 删除空表
expect_success "create empty table" "CREATE TABLE Drop_table_1(id int, t_name char);"
expect_success "drop empty table" "DROP TABLE Drop_table_1;"

# 2. 删除非空表
expect_success "create table 2" "CREATE TABLE Drop_table_2(id int, t_name char);"
expect_success "insert into table 2" "INSERT INTO Drop_table_2 VALUES (1,'OB');"
expect_success "drop non-empty table" "DROP TABLE Drop_table_2;"

# 3. 删除后 DML 应失败，可重建
expect_success "create table 3" "CREATE TABLE Drop_table_3(id int, t_name char);"
expect_success "insert table 3" "INSERT INTO Drop_table_3 VALUES (1,'OB');"
expect_success "drop table 3" "DROP TABLE Drop_table_3;"
expect_failure "insert after drop" "INSERT INTO Drop_table_3 VALUES (2,'OC');"
expect_failure "select after drop" "SELECT * FROM Drop_table_3;"
expect_success "recreate table 3" "CREATE TABLE Drop_table_3(id int, t_name char);"
expect_select_ok "select empty table 3" "SELECT * FROM Drop_table_3;"

# 4. 重复删除 / 删除不存在
expect_success "create table 4" "CREATE TABLE Drop_table_4(id int, t_name char);"
expect_success "drop table 4 first" "DROP TABLE Drop_table_4;"
expect_failure "drop table 4 again" "DROP TABLE Drop_table_4;"
expect_failure "drop non-existent table" "DROP TABLE Drop_table_4_1;"

# 5. 删除后重建同名表
expect_success "create table 5" "CREATE TABLE Drop_table_5(id int, t_name char);"
expect_success "drop table 5" "DROP TABLE Drop_table_5;"
expect_success "recreate table 5" "CREATE TABLE Drop_table_5(id int, t_name char);"
expect_select_ok "select table 5" "SELECT * FROM Drop_table_5;"

# 6. 带索引的表
expect_success "create table 6" "CREATE TABLE Drop_table_6(id int, t_name char);"
expect_success "create index" "CREATE INDEX index_id ON Drop_table_6(id);"
expect_success "insert table 6" "INSERT INTO Drop_table_6 VALUES (1,'OB');"
expect_success "drop table with index" "DROP TABLE Drop_table_6;"
expect_failure "select after drop indexed table" "SELECT * FROM Drop_table_6;"

log "========================================"
log "Results: PASS=$pass FAIL=$fail"
if [[ "$fail" -eq 0 ]]; then
  log "All drop table tests passed."
  exit 0
else
  log "Some tests failed."
  exit 1
fi
