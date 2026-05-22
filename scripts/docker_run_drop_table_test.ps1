# Drop Table 一键编译+测试（Windows + Docker Desktop）
#
# 用法:
#   cd C:\Users\HUAWEI\Desktop\project2\miniob
#   .\scripts\docker_run_drop_table_test.ps1

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

$MountArg = 'type=bind,source=' + $RepoRoot + ',target=/root/miniob'

Write-Host "[miniob] Repository:"
Write-Host $RepoRoot
Write-Host "[miniob] Mount:"
Write-Host $MountArg

Write-Host "[miniob] Pull image oceanbase/miniob (if needed)..."
docker pull oceanbase/miniob
if ($LASTEXITCODE -ne 0) { Write-Error "docker pull failed" }

Write-Host "[miniob] Build and run drop table tests (first run: 10-20 min)..."
# oceanbase/miniob 镜像自带 ENTRYPOINT 会跑 ssh/clone；必须 --entrypoint bash 才能执行测试脚本
docker run --rm `
  --entrypoint bash `
  --mount $MountArg `
  -w /root/miniob `
  oceanbase/miniob `
  -lc "sed -i 's/\r$//' build.sh scripts/*.sh 2>/dev/null; chmod +x scripts/run_drop_table_test.sh && ./scripts/run_drop_table_test.sh"

if ($LASTEXITCODE -eq 0) {
    Write-Host "[miniob] All tests passed."
} else {
    Write-Error "[miniob] Tests failed with exit code $LASTEXITCODE"
}
