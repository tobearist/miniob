# Drop Table 功能测试报告（任务六）

**项目名称**：MiniOB — DROP TABLE 实现  
**工程路径**：`C:\Users\HUAWEI\Desktop\project2\miniob`  
**测试日期**：2026年5月  
**测试结论**：**通过**（25/25 用例全部 PASS）

---

## 一、测试目的

验证在 MiniOB 中实现的 `DROP TABLE` 功能是否满足课程/训练营要求，覆盖：

- 正常删除（空表、有数据表、带索引表）
- 异常删除（重复删除、删除不存在的表）
- 删除后的依赖行为（DML 失败、可重建同名表、查询空表）

---

## 二、测试环境

| 项目 | 配置 |
|------|------|
| 操作系统 | Windows 10 |
| 运行方式 | Docker Desktop + 镜像 `oceanbase/miniob` |
| 源码目录 | `C:\Users\HUAWEI\Desktop\project2\miniob` |
| 编译方式 | `bash build.sh debug --make -j8 observer obclient` |
| 产物路径 | `build_debug/bin/observer` |
| 测试脚本 | `scripts/run_drop_table_test.sh` |
| SQL 客户端 | `scripts/miniob_sql_client.py`（与官方 `miniob_test` 相同协议） |
| 通信方式 | Unix Socket（临时目录 `/tmp/miniob_drop_table_test_*`） |

**说明**：Windows 挂载目录下通过 `sed` 将 `build.sh` 等脚本转为 LF 换行；`build` 软链接在 Windows 挂载时可能失效，测试脚本自动识别 `build_debug/bin` 路径。

---

## 三、测试方法

### 3.1 自动化测试

1. 启动 `observer`（加载 `etc/observer.ini`）
2. 通过 Python 客户端逐条发送 SQL（每条以 `\0` 结束，带 15s 超时）
3. 根据语句类型判断结果：
   - **DDL**（CREATE/DROP/INSERT）：输出含 `SUCCESS` 为通过，含 `FAILURE` 为预期失败
   - **SELECT**：输出不含 `FAILURE` 为通过（空表仅返回表头，如 `id | t_name`）

### 3.2 对照用例

与官方用例 `test/case/test/primary-drop-table.test` 及集成测试 `test/integration_test/test_cases/MiniOB/python/drop_table.py` 场景一致。

### 3.3 执行命令

```powershell
cd C:\Users\HUAWEI\Desktop\project2\miniob
docker run --rm --entrypoint bash `
  --mount "type=bind,source=<工程路径>,target=/root/miniob" `
  -w /root/miniob oceanbase/miniob `
  -lc "sed -i 's/\r$//' build.sh scripts/*.sh; MINIOB_BUILD=0 ./scripts/run_drop_table_test.sh"
```

---

## 四、测试用例设计

### 4.1 用例总览

| 编号 | 分组 | 测试项 | 主要 SQL | 预期 |
|------|------|--------|----------|------|
| 1 | 空表 | 删除空表 | CREATE → DROP | SUCCESS |
| 2 | 非空表 | 删除有数据表 | CREATE → INSERT → DROP | SUCCESS |
| 3 | 删后行为 | 删后 INSERT/SELECT 失败 | DROP 后 INSERT/SELECT | FAILURE |
| 3 | 删后行为 | 重建同名表 | CREATE 同名表 | SUCCESS |
| 3 | 删后行为 | 查询空表 | SELECT * | 返回表头，无 FAILURE |
| 4 | 异常 | 重复删除 | DROP 两次 | 第二次 FAILURE |
| 4 | 异常 | 删除不存在表 | DROP 未创建表 | FAILURE |
| 5 | 重建 | 删后 CREATE 同名 + SELECT | DROP → CREATE → SELECT | SUCCESS / 空结果 |
| 6 | 索引 | 删带索引表 | CREATE INDEX → DROP | SUCCESS |
| 6 | 索引 | 删后 SELECT | SELECT * | FAILURE |

### 4.2 详细步骤与结果

#### 场景 1：删除空表

```sql
CREATE TABLE Drop_table_1(id int, t_name char);
DROP TABLE Drop_table_1;
```

| 步骤 | 预期 | 实测 |
|------|------|------|
| CREATE | SUCCESS | PASS |
| DROP | SUCCESS | PASS |

磁盘上 `Drop_table_1.table`、`Drop_table_1.data` 被删除；内存 catalog 中移除该表。

---

#### 场景 2：删除非空表

```sql
CREATE TABLE Drop_table_2(id int, t_name char);
INSERT INTO Drop_table_2 VALUES (1,'OB');
DROP TABLE Drop_table_2;
```

| 步骤 | 预期 | 实测 |
|------|------|------|
| CREATE / INSERT / DROP | 均为 SUCCESS | 全部 PASS |

说明：**不要求先清空数据**，可直接 DROP。

---

#### 场景 3：删除准确性（删后 DML、重建、查询）

```sql
CREATE TABLE Drop_table_3(id int, t_name char);
INSERT INTO Drop_table_3 VALUES (1,'OB');
DROP TABLE Drop_table_3;
INSERT INTO Drop_table_3 VALUES (2,'OC');   -- 应失败
SELECT * FROM Drop_table_3;                  -- 应失败
CREATE TABLE Drop_table_3(id int, t_name char);
SELECT * FROM Drop_table_3;                  -- 空表，仅表头
```

| 步骤 | 预期 | 实测 |
|------|------|------|
| DROP 后 INSERT | FAILURE | PASS |
| DROP 后 SELECT | FAILURE | PASS |
| 重建表 CREATE | SUCCESS | PASS |
| 重建后 SELECT | 成功，无数据行 | PASS（输出 `id \| t_name`） |

---

#### 场景 4：删除不存在的表 / 重复删除

```sql
CREATE TABLE Drop_table_4(id int, t_name char);
DROP TABLE Drop_table_4;
DROP TABLE Drop_table_4;        -- 重复
DROP TABLE Drop_table_4_1;      -- 从未创建
```

| 步骤 | 预期 | 实测 |
|------|------|------|
| 首次 DROP | SUCCESS | PASS |
| 第二次 DROP | FAILURE | PASS |
| DROP 不存在表 | FAILURE | PASS |

返回码语义：`RC::SCHEMA_TABLE_NOT_EXIST`，客户端显示 **FAILURE**。

---

#### 场景 5：删除后重建同名表

```sql
CREATE TABLE Drop_table_5(id int, t_name char);
DROP TABLE Drop_table_5;
CREATE TABLE Drop_table_5(id int, t_name char);
SELECT * FROM Drop_table_5;
```

| 步骤 | 预期 | 实测 |
|------|------|------|
| DROP / CREATE | SUCCESS | PASS |
| SELECT | 空表（表头） | PASS |

说明：删除后磁盘文件已清理，重建等价于全新建表。

---

#### 场景 6：删除带索引的表

```sql
CREATE TABLE Drop_table_6(id int, t_name char);
CREATE INDEX index_id ON Drop_table_6(id);
INSERT INTO Drop_table_6 VALUES (1,'OB');
DROP TABLE Drop_table_6;
SELECT * FROM Drop_table_6;
```

| 步骤 | 预期 | 实测 |
|------|------|------|
| CREATE INDEX / INSERT / DROP | SUCCESS | PASS |
| DROP 后 SELECT | FAILURE | PASS |

实现按 `TableMeta` 中索引列表删除 `{表名}-{索引名}.index` 文件，无需单独 `DROP INDEX`。

---

## 五、测试结果汇总

```
[drop-table-test] Results: PASS=25 FAIL=0
[drop-table-test] All drop table tests passed.
```

| 统计项 | 数值 |
|--------|------|
| 总用例数 | 25 |
| 通过 | 25 |
| 失败 | 0 |
| 通过率 | 100% |

---

## 六、异常与边界行为说明

| 行为 | 实现策略 | 测试是否覆盖 |
|------|----------|--------------|
| 表不存在 | Resolve + `Db::drop_table` 返回 `SCHEMA_TABLE_NOT_EXIST` | 是 |
| 重复删除 | 同上（catalog 中已无表） | 是 |
| 外键/视图依赖 | MiniOB 基础版无 FK，未实现级联检查 | 不适用 |
| 未提交事务 | 教学版未做复杂事务冲突检测 | 未单独测 |
| DDL 日志 | 无单独 DROP 日志条；靠删文件 + `Db::sync` | 设计如此 |
| LSM 引擎 | `Table::drop` 返回 `UNSUPPORTED` | 未测（本测试为 Heap） |

---

## 七、问题记录与处理

| 问题 | 原因 | 处理 |
|------|------|------|
| Docker 挂载路径为空 | PowerShell 解析 `$var:/path` 中 `C:` 出错 | 改用 `--mount type=bind,source=...` |
| 镜像 ENTRYPOINT 跑 SSH | 未覆盖入口 | 增加 `--entrypoint bash` |
| `build.sh` 报 `$'\r'` | Windows CRLF | 容器内 `sed` 转 LF |
| 找不到 observer | 实际在 `build_debug/bin` | 脚本多路径探测 |
| 测试卡住 | `obclient` 交互式不适合管道 | 改用 Python 客户端 |
| SELECT 误判 FAIL | 空表只返回表头无 `SUCCESS` | 增加 `expect_select_ok` |

---

## 八、结论

1. **DROP TABLE 核心功能正确**：可删除空表、非空表、带索引表；catalog 与磁盘文件一致清理。  
2. **异常处理符合预期**：重复删除、删除不存在表均返回 FAILURE。  
3. **删除后行为正确**：删后 DML 失败；允许重建同名表；新表为空。  
4. **任务五/六测试目标达成**，可进入训练营提测或撰写项目总结。

---

## 九、附录：实现模块索引（便于审查）

| 模块 | 文件 |
|------|------|
| 语法解析 | `src/observer/sql/parser/yacc_sql.y`（已有） |
| Stmt | `sql/stmt/drop_table_stmt.cpp` |
| Executor | `sql/executor/drop_table_executor.cpp` |
| 分发 | `sql/stmt/stmt.cpp`、`sql/executor/command_executor.cpp` |
| 存储 | `storage/db/db.cpp`（`drop_table`）、`storage/table/table.cpp`（`drop`） |
