# ALTER TABLE 测试报告

> 工程：`C:\Users\HUAWEI\Desktop\project2\miniob`  
> 功能：`ALTER TABLE ... ADD [COLUMN] col type`  
> 测试日期：2026-05-21

---

## 一、测试环境

| 项 | 值 |
|----|-----|
| 运行方式 | Docker `oceanbase/miniob`，`--entrypoint bash` |
| 挂载 | Windows 路径 bind 到 `/root/miniob` |
| 脚本 | `scripts/run_alter_table_test.sh` |
| 客户端 | `scripts/miniob_sql_client.py`（Unix socket，15s 超时） |
| 编译产物 | `build_debug/bin/observer` |

**推荐命令（Windows PowerShell）：**

```powershell
cd C:\Users\HUAWEI\Desktop\project2\miniob
.\scripts\docker_run_alter_table_test.ps1
```

---

## 二、测试结果摘要

```
PASS=18  FAIL=0
All alter table tests passed.
```

DROP TABLE 回归（`run_drop_table_test.sh`）：**25/25 PASS**（未破坏已有逻辑）。

---

## 三、用例清单

| # | 场景 | SQL 要点 | 期望 |
|---|------|----------|------|
| 1 | 空表加列 | `CREATE` → `ALTER ADD COLUMN score int` | SUCCESS |
| 2 | 加列后 DESC | `DESC Alter_t1` | 无 FAILURE |
| 3 | 有数据加列 | `INSERT` 一行 → `ALTER ADD extra int` | SUCCESS |
| 4 | 加列后查询 | `SELECT *` | 旧列保留，新列 **0** |
| 5 | 新列写入 | `INSERT` 三列值 | SUCCESS |
| 6 | 两行查询 | `SELECT *` | 无 FAILURE |
| 7 | **重复加列** | 再次 `ADD extra` | **FAILURE** |
| 8 | **表不存在** | `ALTER` 不存在的表 | **FAILURE** |
| 9 | **带索引表加列** | `CREATE INDEX` → `ALTER ADD` | SUCCESS |
| 10 | 索引表查询 | `SELECT *` | 无 FAILURE |
| 11 | 省略 COLUMN | `ALTER ... ADD flag int` | SUCCESS |
| 12 | DROP 回归 | `DROP TABLE Alter_t1` | SUCCESS |

---

## 四、行为说明

### 4.1 正常路径

- 新列追加在 `TableMeta` 尾部，旧字段 offset 不变。
- 已有行：新列内存区域为 **0**（与 `memset` 默认一致）。
- 数据页 `record_size` 变化后，通过 **重建 `.data` 文件** 再插回全部行；索引文件删除后按元数据 **重建 B+ 树**。

### 4.2 异常路径

| 场景 | 行为 |
|------|------|
| 表不存在 | Resolve/执行前检查，`SCHEMA_TABLE_NOT_EXIST` → FAILURE |
| 列名已存在 | `SCHEMA_TABLE_EXIST` → FAILURE |
| 加列后重复 ADD | FAILURE（用例 7 验证） |

### 4.3 与「有依赖」的关系

- 表上已有 **B+ 树索引** 时，加列后索引键字段未变，RID 重新生成；实现上 **删除旧 `.index` 并全表重建索引**。
- 测试 9–10 验证：加列后 `SELECT` 仍成功。

---

## 五、已知限制

1. 仅支持 **ADD COLUMN**（Heap 引擎）。
2. 新列默认值固定为 **二进制零**，不支持 `DEFAULT` 子句。
3. 加列过程若中途失败，可能留下不一致文件（与 DROP 相同，未做完整事务回滚）。

---

## 六、缺陷修复记录

| 问题 | 原因 | 修复 |
|------|------|------|
| 有数据表 ALTER 后 observer 崩溃 | `Record` 析构 `free` 与 `new[]` 不匹配 | 迁移行改用 `malloc` + `set_data_owner` |

---

## 七、相关文件

| 类型 | 路径 |
|------|------|
| 设计 | `docs/ALTER_TABLE_DESIGN.md` |
| 总结 | `docs/ALTER_TABLE_PROJECT_SUMMARY.md` |
| 自动化测试 | `scripts/run_alter_table_test.sh` |
| 官方风格用例 | `test/case/test/primary-alter-table.test` |
