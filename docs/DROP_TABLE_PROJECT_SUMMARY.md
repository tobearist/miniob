# Drop Table 项目总结（任务七）

**课程/项目**：MiniOB 数据库内核实战 — DROP TABLE 功能实现  
**工程路径**：`C:\Users\HUAWEI\Desktop\project2\miniob`  
**完成时间**：2026年5月  

---

## 一、项目概述

本项目在 MiniOB 教学型数据库中，参考 **CREATE TABLE** 的现有实现，完成 **DROP TABLE** 从 SQL 解析到存储落盘的端到端开发，并通过自动化测试验证（25/25 用例通过）。

### 1.1 任务完成情况

| 序号 | 任务 | 完成情况 |
|------|------|----------|
| 1 | 分析 Create Table 实现原理 | 已完成 |
| 2 | 设计 Drop Table 整体方案 | 已完成 |
| 3 | 关键逻辑设计 | 已完成 |
| 4 | 编写核心代码 | 已完成 |
| 5 | 设计测试用例并执行测试 | 已完成（PASS=25） |
| 6 | 编写测试报告 | 已完成（见 `DROP_TABLE_TEST_REPORT.md`） |
| 7 | 项目总结 | 本文档 |

### 1.2 核心交付物

- **实现代码**：4 个新文件 + 5 个修改文件（SQL 层 + 存储层）
- **测试脚本**：`scripts/run_drop_table_test.sh`、`scripts/miniob_sql_client.py` 等
- **文档**：设计方案（任务二）、测试报告（任务六）、本总结（任务七）

---

## 二、技术方案回顾

### 2.1 整体思路

DROP TABLE 与 CREATE TABLE **对称**：走同一套 SQL 流水线，DDL 不生成执行计划，由专用 Executor 调用存储层。

```
DROP TABLE t
  → Parse（已有 yacc）
  → DropTableStmt::create（表必须存在）
  → DropTableExecutor
  → Db::drop_table（catalog + delete Table*）
  → Table::drop（sync → 关闭引擎 → 删除 .table/.data/.index）
  → CommandExecutor 内 Db::sync()
```

### 2.2 与 Create Table 的对照

| 阶段 | CREATE TABLE | DROP TABLE |
|------|--------------|------------|
| Resolve | 表不得已存在 | 表必须存在 |
| 存储动作 | 写元数据与数据文件 | 关资源、删文件 |
| catalog | `opened_tables_` 插入 | `erase` + `delete` |
| 持久化 | 直接写盘 + DDL 后 sync | 删文件 + DDL 后 sync |

### 2.3 关键设计决策

1. **不实现 DDL 日志条**：与现有 CREATE 一致，依赖文件系统状态；重启时 `open_all_tables` 扫描 `*.table`。
2. **先释放内存再删文件**：`engine_.reset()` 关闭 Buffer Pool 与索引，避免文件占用。
3. **索引随表删除**：遍历 `TableMeta` 中索引列表删除 `.index` 文件。
4. **错误码统一**：表不存在 → `SCHEMA_TABLE_NOT_EXIST` → 客户端 **FAILURE**。

---

## 三、实现清单（便于复盘与答辩）

### 3.1 新增文件

| 文件 | 职责 |
|------|------|
| `sql/stmt/drop_table_stmt.h/.cpp` | 语义解析，校验表存在 |
| `sql/executor/drop_table_executor.h/.cpp` | 调用 `Db::drop_table` |

### 3.2 修改文件

| 文件 | 改动 |
|------|------|
| `sql/stmt/stmt.cpp` | `SCF_DROP_TABLE` 分支 |
| `sql/executor/command_executor.cpp` | `StmtType::DROP_TABLE` 分发 |
| `storage/db/db.h/.cpp` | `Db::drop_table` |
| `storage/table/table.h/.cpp` | `Table::drop` |
| `storage/default/default_handler.cpp` | 转发 `drop_table`（与 create 对称） |

---

## 四、遇到的问题与解决方案

### 4.1 原理与设计阶段

| 问题 | 解决方案 | 收获 |
|------|----------|------|
| 不清楚 DDL 是否要写 redo 日志 | 阅读 `Db::sync`、`LogModule`，确认 CREATE 也不记 DDL 条，靠文件 + sync | 区分**应用日志**与 **CLog/redo**；DDL 持久化靠文件 |
| Drop 与 Create 如何对称 | 画流程图，按 Stage 逐层对照源码 | 先找“对称点”再写代码，减少遗漏 |

### 4.2 编码与环境阶段

| 问题 | 解决方案 | 收获 |
|------|----------|------|
| Windows 本机无 cmake，无法直接编译 | 使用 Docker 镜像 `oceanbase/miniob` | 开发环境容器化是常见做法 |
| PowerShell 禁止执行 `.ps1` | `Set-ExecutionPolicy RemoteSigned` 或用 `docker run` 一行命令 | 了解 Windows 脚本安全策略 |
| Docker `-v C:...` 挂载为空 | 改用 `--mount type=bind,source=...`；避免 `$var:` 被误解析 | PowerShell 与 Docker 路径要单独处理 |
| 镜像默认 ENTRYPOINT 跑 SSH | 增加 `--entrypoint bash` | 跑自定义命令必须覆盖 ENTRYPOINT |
| `build.sh` 报 `$'\r'` | 容器内 `sed -i 's/\r$//'`；增加 `.gitattributes` | 跨平台开发必须注意 **LF/CRLF** |
| 编译后找不到 observer | 实际在 `build_debug/bin`，Windows 下 `build` 软链接常失效 | 测试脚本应探测多个 build 目录 |
| 全量 `make` 耗时长 | 改为 `make observer obclient` | 只编目标，提高迭代效率 |

### 4.3 测试阶段

| 问题 | 解决方案 | 收获 |
|------|----------|------|
| `echo SQL \| obclient` 卡住 | `obclient` 是交互式程序；改用 Python 客户端发 `\0` 结尾协议 | 测 MiniOB 应参考 `miniob_test.py` 通信方式 |
| SELECT 空表被判 FAIL | 空表只返回表头 `id \| t_name`，无 SUCCESS 字样 | 断言要区分 **DDL 与 DML/查询** 的输出格式 |
| 官方 `miniob_test.py` 无 result 文件 | 自写 `run_drop_table_test.sh` 用 SUCCESS/FAILURE 断言 | 测试要适配项目现状，不能盲目照搬工具 |

---

## 五、测试结论（摘要）

- **环境**：Windows + Docker + `build_debug/bin/observer`
- **结果**：**25/25 PASS**，`All drop table tests passed`
- **覆盖**：空表/非空表/带索引、重复删除、删不存在表、删后 DML、重建同名表

详细用例与 SQL 见：`docs/DROP_TABLE_TEST_REPORT.md`。

---

## 六、收获与体会

### 6.1 对数据库内核的理解

1. **SQL 引擎分层清晰**：Parse → Resolve → Execute → Storage，DDL 走 CommandExecutor 短路，不经过优化器。
2. **catalog 与磁盘一致**：`opened_tables_` 是内存 catalog；`.table` / `.data` / `.index` 是持久化；DROP 必须两边同时清理。
3. **资源生命周期**：Table → TableEngine → BufferPool/Index，删除顺序应是 **sync → 析构关闭句柄 → unlink 文件**。

### 6.2 工程实践能力

1. **读代码比堆代码重要**：先顺着 CREATE TABLE 把调用链走通，DROP 实现量不大但位置要准。
2. **测试驱动验证**：实现完用脚本回归，比手工敲 SQL 可靠。
3. **环境问题是常态**：CRLF、路径、Docker 挂载、客户端协议都要单独排查，应预留时间在环境上。

### 6.3 团队协作建议（若分工实现）

| 角色 | 建议负责 |
|------|----------|
| 同学 A | 方案设计、存储层 `Db::drop_table` / `Table::drop` |
| 同学 B | SQL 层 Stmt + Executor + 联调 |
| 测试/文档 | 脚本、测试报告、本总结 |

接口约定：`Db::drop_table(const char *)` 返回 RC；表不存在统一 `SCHEMA_TABLE_NOT_EXIST`。

### 6.4 可改进方向（未做或后续可做）

1. **删除失败回滚**：当前删文件若部分失败，catalog 可能不一致；可加强原子性（先 rename 再删）。
2. **LSM 存储引擎**：`Table::drop` 对 LSM 返回 `UNSUPPORTED`，若课程要求需补实现。
3. **并发与锁**：文档注明 Db 无表级锁，生产库需额外设计。
4. **与训练营对齐**：可用 `primary-drop-table.test` 生成 result 后接官方 `miniob_test.py` 二次验证。

---

## 七、个人反思（可据实删改）

通过从“读 CREATE”到“写 DROP”的完整链路，第一次把 MiniOB 从**一条 SQL 字符串**追到**磁盘文件变化**的全过程串了起来。前期在环境上踩坑较多（Docker、CRLF、客户端协议），但也加深了对“能编过”和“测得过”之间差距的理解。最终实现与测试全部通过后，对 **DDL 本质上是改 schema 与文件** 有了更直观的认识，也为后续学习事务、日志和恢复打下基础。

---

## 八、参考文献与代码位置

| 资料 | 路径 |
|------|------|
| 教材/实验文档 | `从0到1 OceanBase原生分布式数据库内核实战基础版.docx` |
| 官方 drop 用例 | `test/case/test/primary-drop-table.test` |
| MiniOB 仓库 | https://github.com/oceanbase/miniob |
| 测试报告 | `docs/DROP_TABLE_TEST_REPORT.md` |
| 测试说明 | `scripts/README_DROP_TABLE_TEST.md` |

---

## 九、一句话总结

> 在 MiniOB 中按 CREATE TABLE 的对称路径实现 DROP TABLE，通过释放 TableEngine 资源并删除元数据/数据/索引文件完成表注销，经 25 项自动化测试全部通过，完成了从原理分析、方案设计、编码实现到测试验证的完整闭环。
