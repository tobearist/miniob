# ALTER TABLE 项目总结

> 实验：MiniOB `ALTER TABLE ADD COLUMN`  
> 工程：`C:\Users\HUAWEI\Desktop\project2\miniob`

---

## 一、完成内容

| 任务 | 状态 | 产出 |
|------|------|------|
| 1. 设计方案 + 流程图 | ✅ | `docs/ALTER_TABLE_DESIGN.md` |
| 2. 核心代码 | ✅ | Parser / Stmt / Executor / `HeapTableEngine::add_column` |
| 3. 测试用例与执行 | ✅ | `scripts/run_alter_table_test.sh`，**18/18 PASS** |
| 4. 测试报告 | ✅ | `docs/ALTER_TABLE_TEST_REPORT.md` |
| 5. 项目总结 | ✅ | 本文档 |

**说明**：课程原文中的「[粘贴课程要求]」未附带具体条文；实现按训练营常见 **`ALTER TABLE t ADD COLUMN col type`** 语义完成。若你的题目还要求 `DROP COLUMN` / `RENAME` 等，可在此基础上扩展。

---

## 二、实现要点（与 DROP TABLE 对照）

```
ALTER TABLE t ADD COLUMN c INT
  → SCF_ALTER_TABLE, AlterTableSqlNode
  → AlterTableStmt::create（表存在、列不存在）
  → AlterTableExecutor → Db::alter_table_add_column
  → HeapTableEngine::add_column
       扫描旧行 → 更新 TableMeta → 重建 .data → 插回 → 重建 .index
  → CommandExecutor: Db::sync()
```

对称点：与 `DropTableStmt` 相同走 **Parse → Resolve → CommandExecutor**；`stmt_type_ddl()` 已加入 `ALTER_TABLE`。

---

## 三、遇到的问题与解决方案

### 3.1 定长记录无法原地扩列

**问题**：页头 `record_real_size` 在建页时固定，行变长后无法 `update_record` 原地扩容。  
**解决**：导出全部旧行 → 删 `.data` → 按新 `record_size` 新建数据文件并插入；索引同样删文件后重建。

### 3.2 AddressSanitizer：new[] / free 不匹配

**问题**：有数据表执行 ALTER 后 observer 崩溃。  
**原因**：迁移时使用 `new char[]`，`Record::~Record` 使用 `free`。  
**解决**：与 `Table::make_record` 一致，改用 `malloc` + `set_data_owner`。

### 3.3 Windows + Docker 测试

与 DROP TABLE 相同：CRLF 用 `sed -i 's/\r$//'`；用 `miniob_sql_client.py`，不用 obclient 管道。

---

## 四、收获

1. **DDL 比 DROP 复杂**：不仅要改 catalog（`.table`），还要考虑数据页格式与二级索引一致性。  
2. **元数据与数据分离**：`create_index` 里「先改内存 meta 再 rename 刷盘」的模式可复用到 ALTER。  
3. **测试驱动**：18 条脚本用例覆盖空表、有数据、重复列、不存在表、带索引、语法变体，并保留 DROP 回归。  
4. **继承 PROJECT_CONTEXT**：复用 Docker 编译、socket 客户端、DDL 后 `sync()` 等既有经验，缩短调试时间。

---

## 五、代码索引（便于 Code Review）

| 模块 | 文件 |
|------|------|
| 词法/语法 | `lex_sql.l`, `yacc_sql.y`, `parse_defs.h` |
| Stmt | `alter_table_stmt.h/.cpp`, `stmt.cpp`, `stmt.h` |
| Executor | `alter_table_executor.h/.cpp`, `command_executor.cpp` |
| 存储 | `table_meta.cpp`（`add_field`）, `heap_table_engine.cpp`（`add_column`）, `db.cpp`, `table.cpp` |

---

## 六、后续可扩展方向

- `ALTER TABLE t DROP COLUMN col`
- `RENAME TABLE` / 改列类型（需更重的数据迁移）
- 加列时支持 `DEFAULT` 表达式
- 失败时原子回滚（临时目录 + 整体 rename）

---

*与 `docs/PROJECT_CONTEXT.md` 配套；Drop Table 25/25 + Alter Table 18/18 均已在本仓库验证。*
