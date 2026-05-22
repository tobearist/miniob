# MiniOB Drop Table 项目上下文（Context 压缩）

> **用途**：在新对话（如 Alter Table）开始时，将本文档提供给 AI，可快速恢复工程状态、已完成工作与踩坑经验。  
> **工程根目录**：`C:\Users\HUAWEI\Desktop\project2\miniob`  
> **教材**：`C:\Users\HUAWEI\Desktop\project2\从0到1 OceanBase原生分布式数据库内核实战基础版.docx`

---

## 一、项目背景与任务清单

用户完成 OceanBase MiniOB 训练营式作业，共 7 项任务，**均已完成**：

| # | 任务 | 状态 | 产出位置 |
|---|------|------|----------|
| 1 | 分析 Create Table 实现原理 + 流程图 | ✅ | 对话分析；见下文 §三 |
| 2 | Drop Table 整体设计方案 + 设计图 | ✅ | 对话 + 任务二设计 |
| 3 | 关键逻辑设计（伪代码/检查清单） | ✅ | 对话任务三 |
| 4 | 编写 Drop Table 核心代码 | ✅ | `src/observer/...` 见 §五 |
| 5 | 测试用例 + 功能测试 | ✅ | `scripts/run_drop_table_test.sh`，**25/25 PASS** |
| 6 | 测试报告 | ✅ | `docs/DROP_TABLE_TEST_REPORT.md` |
| 7 | 项目总结 | ✅ | `docs/DROP_TABLE_PROJECT_SUMMARY.md` |

**Alter Table（ADD COLUMN）**：已实现，自动化测试 **18/18 PASS**（`scripts/run_alter_table_test.sh`）；设计见 `docs/ALTER_TABLE_DESIGN.md`。

---

## 二、教材与 MiniOB 架构（任务一核心，来自 docx + 源码）

### 2.1 教材定位

- 课程：《从0到1 OceanBase 原生分布式数据库内核实战》
- MiniOB：OceanBase 开源的教学型单机能跑通 SQL 引擎的小型数据库
- 官方仓库：https://github.com/oceanbase/miniob  
- 训练营常用分支名：`miniob_test`（克隆时注意分支是否存在，main 亦可）

### 2.2 教材中的 MiniOB 简化架构（第 1 章）

```
客户端 → 网络模块 → Parser → Resolver → (Transformer/Optimizer) → Executor → 存储层
                                                              ↓
                                                    Buffer Pool / 记录 / 索引
```

- **Resolver**：语法树细化为 Stmt；如 `select *` 展开为字段列表；**表不存在可提前报错**
- **Optimizer**：为 DML 选路径；**DDL 一般不生成 LogicalPlan**（返回 `UNIMPLEMENTED` 后跳过）
- **Executor**：DDL 走 `CommandExecutor` + 专用 Executor；DML 走 `PhysicalOperator` 树

### 2.3 教材/Debug 文档中的旧版关键接口（已演进，对照用）

旧调试文档（`docs/docs/dev-env/miniob-how-to-debug.md`）列出的结构：

```
parse_def.h: CreateTable, DropTable, SqlCommandFlag, Queries
Db::create_table, Db::find_table
Table::create, Table::insert_record, ...
ExecuteStage / DefaultHandler / DefaultStorageStage  // 旧架构
```

**当前主干（2024+）** 已改为多 Stage：

| 教材/旧名 | 当前实现 |
|-----------|----------|
| `parse` → Query | `ParseStage` → `ParsedSqlNode` |
| Resolver | `ResolveStage` → `Stmt::create_stmt` |
| ExecuteStage | `ExecuteStage` → `CommandExecutor` 或算子树 |
| `DefaultHandler::create_table` | 主路径：`CreateTableExecutor` → `Db::create_table` |
| `DefaultHandler::drop_table` | 已实现转发：`Db::drop_table`（原为 UNIMPLEMENTED） |

### 2.4 SQL 执行流水线（Create/Drop 通用）

**入口**：`SqlTaskHandler::handle_sql` 或 `SessionStage::handle_sql`

```
QueryCache → Parse → Resolve → Optimize → Execute → 写回客户端
```

- **Parse**：`yacc_sql.y` + `ParseStage`；产出 `ParsedSqlNode`，flag 如 `SCF_CREATE_TABLE` / `SCF_DROP_TABLE`
- **Resolve**：`Stmt::create_stmt`；CREATE 不需要表存在，DROP 需要 `find_table` 非空
- **Optimize**：`LogicalPlanGenerator` 对 CREATE/DROP 走 `default` → `RC::UNIMPLEMENTED`；`handle_sql` 中该码**不算失败**，继续 Execute
- **Execute**：无 `physical_operator` 时 → `CommandExecutor` → 各 `*Executor`
- **DDL 成功后**：`CommandExecutor` 内 `stmt_type_ddl()` → `Db::sync()`（刷脏页 + check_point，**不是** DDL 专用 redo 条）

### 2.5 DDL vs DML 持久化（重要认知）

| 类型 | 持久化方式 | 日志 |
|------|------------|------|
| **DDL**（CREATE/DROP TABLE） | 直接改磁盘文件（`.table` `.data` `.index`） | 无 `LogModule::DDL`；DDL 后 `sync()` |
| **DML** | Buffer Pool + Record/Index 修改 | CLog：`RECORD_MANAGER` / `BPLUS_TREE` / `TRANSACTION` 等 |

重启：`open_all_tables()` 扫描 `*.table` + `recover()` 回放 DML 的 redo。

### 2.6 Create Table 实现链（任务一结论，Drop 对照此链）

```
CREATE TABLE t (...)
  → yacc: SCF_CREATE_TABLE, CreateTableSqlNode
  → CreateTableStmt::create（校验 storage_format）
  → CreateTableExecutor → Db::create_table
       → 检查 opened_tables_ 无重名
       → Table::create: O_EXCL 建 .table, TableMeta::init, serialize, bpm.create_file(.data), HeapTableEngine::open
       → opened_tables_[name] = table
  → CommandExecutor: Db::sync()
```

**磁盘文件**（`meta_util.cpp`）：

- `{dbpath}/{table}.table` — 元数据  
- `{dbpath}/{table}.data` — 数据  
- `{dbpath}/{table}-{index}.index` — 索引  
- `{dbpath}/{table}.lob` — 可选 LOB  

---

## 三、Drop Table 设计方案（任务二/三摘要）

### 3.1 对称设计

```
DROP TABLE t
  → SCF_DROP_TABLE, DropTableSqlNode
  → DropTableStmt::create（db->find_table 必须存在 → else SCHEMA_TABLE_NOT_EXIST）
  → DropTableExecutor → Db::drop_table
  → Table::drop
  → opened_tables_.erase + delete table
  → Db::sync()
```

### 3.2 Table::drop 步骤

1. 拷贝 `db_path`、`table_name`、索引名列表（`engine_.reset()` 前）  
2. `engine_->sync()`；`engine_.reset()`（HeapTableEngine 析构：close BP、delete indexes）  
3. `delete lob_handler_`  
4. `remove`：各 `.index` → `.data` → `.lob`（若存在）→ `.table` → `.table.tmp`  
5. LSM 引擎：`Table::drop` 返回 `UNSUPPORTED`（训练营 Heap 测试未覆盖）

### 3.3 错误语义

| 场景 | RC | 客户端 |
|------|-----|--------|
| 表不存在 / 重复 DROP | `SCHEMA_TABLE_NOT_EXIST` | FAILURE |
| 删文件失败 | `IOERR_*` | FAILURE |
| 成功 | `SUCCESS` | SUCCESS |

**不回收** `next_table_id_`；删后 CREATE 同名表用新 id，测试允许。

---

## 四、已实现代码清单（任务四）

### 4.1 新增

- `src/observer/sql/stmt/drop_table_stmt.h`
- `src/observer/sql/stmt/drop_table_stmt.cpp`
- `src/observer/sql/executor/drop_table_executor.h`
- `src/observer/sql/executor/drop_table_executor.cpp`

### 4.2 修改

- `src/observer/sql/stmt/stmt.cpp` — `case SCF_DROP_TABLE`
- `src/observer/sql/executor/command_executor.cpp` — `case StmtType::DROP_TABLE`
- `src/observer/storage/db/db.h` / `db.cpp` — `Db::drop_table`
- `src/observer/storage/table/table.h` / `table.cpp` — `Table::drop` + 匿名 `remove_file_if_exists`
- `src/observer/storage/default/default_handler.cpp` — `drop_table` 转发到 `Db::drop_table`

### 4.3 Parser（原本就有，未改）

```yacc
drop_table_stmt:
    DROP TABLE ID { SCF_DROP_TABLE; drop_table.relation_name = $3; }
```

### 4.4 stmt_type_ddl 已包含 DROP_TABLE

`CommandExecutor` 末尾对 DDL 自动 `sync()`。

---

## 五、测试体系（任务五/六）

### 5.1 官方用例

- `test/case/test/primary-drop-table.test` — 与训练营一致  
- `test/integration_test/test_cases/MiniOB/python/drop_table.py` — 需 MySQL 对比，可选  

**注意**：`primary-drop-table` **无** `result/primary-drop-table.result`，直接跑 `miniob_test.py` 会对比失败。

### 5.2 自研自动化脚本（推荐）

| 文件 | 作用 |
|------|------|
| `scripts/run_drop_table_test.sh` | 25 条用例，PASS/FAIL 统计 |
| `scripts/miniob_sql_client.py` | Unix socket + `\0` 协议，15s 超时（**勿用 obclient 管道**） |
| `scripts/docker_run_drop_table_test.ps1` | Windows 一键 Docker |
| `scripts/docker_run_drop_table_test.sh` | Linux/ECS 一键 |
| `scripts/README_DROP_TABLE_TEST.md` | 环境说明 |

### 5.3 测试结果（用户已验证）

```
PASS=25 FAIL=0
All drop table tests passed.
```

用例覆盖：空表/非空表/带索引删除；重复 DROP；删不存在表；删后 INSERT/SELECT 失败；删后重建同名；SELECT 空表（仅表头）。

### 5.4 Windows + Docker 推荐命令

```powershell
cd C:\Users\HUAWEI\Desktop\project2\miniob
docker run --rm --entrypoint bash `
  --mount "type=bind,source=$((Get-Location).Path),target=/root/miniob" `
  -w /root/miniob oceanbase/miniob `
  -lc "sed -i 's/\r$//' build.sh scripts/*.sh; MINIOB_BUILD=0 ./scripts/run_drop_table_test.sh"
```

编译（首次）：

```bash
bash build.sh debug --make -j8 observer obclient
# 二进制在 build_debug/bin/observer（build 软链在 Windows 挂载常失效）
```

---

## 六、环境与踩坑全集（必读本节）

| 问题 | 原因 | 解决 |
|------|------|------|
| Windows 无 cmake | 未装本地工具链 | Docker `oceanbase/miniob` 或 Dev Container |
| `.ps1` 无法执行 | ExecutionPolicy | `Set-ExecutionPolicy RemoteSigned` |
| Docker `-v` 为空 `:/root/miniob` | PowerShell 把 `$var:` 当作用域 | `--mount type=bind,source=绝对路径,target=/root/miniob` |
| 容器跑 SSH/clone | 镜像 ENTRYPOINT | **`--entrypoint bash`** |
| `build.sh` `$'\r'` | Windows CRLF | 容器 `sed -i 's/\r$//'`；已加 `.gitattributes` `*.sh eol=lf` |
| observer not found | 产物在 `build_debug/bin` | `resolve_build_bin_dir()` 探测多目录 |
| 编译很久 | 默认 make 全量单测 | `make observer obclient` |
| 测试卡住 | `echo \| obclient` 交互式 | **`miniob_sql_client.py`** |
| SELECT 误判 FAIL | 空表只输出 `id \| t_name` | `expect_select_ok`：无 FAILURE 即过 |
| Clock skew 警告 | Win 挂载时间戳 | 可忽略 |

### Dev Container

`.devcontainer/devcontainer.json`：

- image: `oceanbase/miniob`
- workspaceFolder: `/root/miniob`
- 用 Cursor「在容器中重新打开」`project2/miniob` 文件夹

---

## 七、相关文档索引

| 文档 | 路径 |
|------|------|
| 测试报告 | `docs/DROP_TABLE_TEST_REPORT.md` |
| 项目总结 | `docs/DROP_TABLE_PROJECT_SUMMARY.md` |
| 测试说明 | `scripts/README_DROP_TABLE_TEST.md` |
| SQL Parser 设计 | `docs/docs/design/miniob-sql-parser.md` |
| 调试入门 | `docs/docs/dev-env/miniob-how-to-debug.md` |
| 编译 | `docs/docs/dev-env/how-to-compile.md`（若存在） |
| 本 Context | `docs/PROJECT_CONTEXT.md` |

---

## 八、给 Alter Table 新对话的提示

1. **先读 CREATE TABLE + 本 DROP 实现**，ALTER 可能涉及 `TableMeta` 变更、数据迁移、索引重建，比 DROP 复杂。  
2. **Parser**：查 `yacc_sql.y` 是否已有 `ALTER TABLE` 或需新增；`parse_defs.h` 增加 SqlNode。  
3. **Stmt/Executor**：仿 `CreateTableStmt` / `DropTableStmt` 模式；`stmt_type_ddl()` 需包含新类型。  
4. **存储**：可能需改 `TableMeta` 并 rewrite `.table` 文件、记录格式变更；注意 Buffer Pool 中已打开表。  
5. **测试**：参考 `primary-drop-table.test` 风格；用 Python 客户端，不用 obclient 管道；Windows 用 Docker + CRLF 处理。  
6. **grep 起点**：`SCF_ALTER`、`AlterTable`、`alter_table` 在 `src/observer` 搜索现有桩代码。

### 建议首批阅读文件

```
src/observer/sql/parser/yacc_sql.y
src/observer/sql/parser/parse_defs.h
src/observer/sql/stmt/stmt.cpp
src/observer/sql/executor/command_executor.cpp
src/observer/storage/db/db.cpp
src/observer/storage/table/table.cpp
src/observer/storage/table/table_meta.cpp
src/observer/storage/table/heap_table_engine.cpp  // create_index 会改 meta
```

---

## 九、对话中形成的关键结论（压缩）

1. **DDL 不写专用日志条**；Drop/Create 都靠文件 + `sync()`。  
2. **Resolve 阶段** DROP 检查表存在；CREATE 检查表不存在。  
3. **无 FK**；删表时索引随 `TableMeta` 删除文件即可。  
4. **队友协作**：任务四 9 个文件可独立提交；测试脚本在 `scripts/`。  
5. **工程路径固定**：`C:\Users\HUAWEI\Desktop\project2\miniob`（用户已从 Desktop 根目录迁入 project2）。

---

## 十、新对话开场模板（复制给 AI）

```
我在 MiniOB 工程实现 Alter Table，请先阅读：
@docs/PROJECT_CONTEXT.md
@docs/DROP_TABLE_TEST_REPORT.md（可选）

工程路径：C:\Users\HUAWEI\Desktop\project2\miniob
已完成 Drop Table（代码在 src/observer，测试 25/25 PASS）。
请先分析现有 ALTER 相关代码（若有），再给出实现方案。
测试环境：Windows + Docker oceanbase/miniob，注意 CRLF 与 --entrypoint bash。
```

---

*文档版本：Drop Table 任务闭环后生成，供 Alter Table 及后续实验继承上下文。*
