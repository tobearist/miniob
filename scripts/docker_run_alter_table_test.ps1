# Windows 一键在 Docker 中运行 ALTER TABLE 测试
# 用法: .\scripts\docker_run_alter_table_test.ps1

$RepoRoot = (Get-Location).Path
if (-not (Test-Path "$RepoRoot\build.sh")) {
    Write-Error "请在 miniob 工程根目录执行此脚本"
    exit 1
}

docker run --rm --entrypoint bash `
  --mount "type=bind,source=$RepoRoot,target=/root/miniob" `
  -w /root/miniob oceanbase/miniob `
  -lc "sed -i 's/\r$//' build.sh scripts/*.sh 2>/dev/null; chmod +x scripts/run_alter_table_test.sh && MINIOB_BUILD=1 ./scripts/run_alter_table_test.sh"
