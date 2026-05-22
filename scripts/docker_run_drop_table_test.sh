#!/bin/bash
# Drop Table 一键编译+测试（Linux ECS / WSL）
# 工程路径: /mnt/c/Users/HUAWEI/Desktop/project2/miniob 或 ECS 上的同名目录
#
# 用法:
#   cd /path/to/project2/miniob
#   chmod +x scripts/docker_run_drop_table_test.sh
#   ./scripts/docker_run_drop_table_test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPDIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$TOPDIR"

echo "[miniob] Repository: $TOPDIR"
docker pull oceanbase/miniob

docker run --rm \
  --entrypoint bash \
  --mount "type=bind,source=${TOPDIR},target=/root/miniob" \
  -w /root/miniob \
  oceanbase/miniob \
  -lc 'chmod +x scripts/run_drop_table_test.sh && ./scripts/run_drop_table_test.sh'
