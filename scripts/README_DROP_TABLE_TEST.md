# Drop Table 测试指南（任务五）

**本仓库路径（Windows）：**

```
C:\Users\HUAWEI\Desktop\project2\miniob
```

方式 **A（Dev Container）**、**B（WSL2）**、**C（Docker 一键脚本）** 都可以，本质都是在 **Linux** 里编译并运行 `observer`。

---

## 零、最快方式（推荐）

### Windows + Docker Desktop

```powershell
cd C:\Users\HUAWEI\Desktop\project2\miniob
.\scripts\docker_run_drop_table_test.ps1
```

### Linux ECS / WSL

```bash
cd /mnt/c/Users/HUAWEI/Desktop/project2/miniob   # 或 ECS 上实际路径
chmod +x scripts/docker_run_drop_table_test.sh
./scripts/docker_run_drop_table_test.sh
```

成功输出：`All drop table tests passed.`

---

## 一、三种环境对比

| 方式 | 适用场景 | 说明 |
|------|----------|------|
| **A Dev Container** | 本地 Cursor/VS Code | 镜像 `oceanbase/miniob`，在容器中打开工程 |
| **B WSL2** | Windows 本机 | `apt install` 依赖后 `build.sh` |
| **C ECS + Docker** | 华为云服务器 | 与 A 相同镜像，`docker run` 挂载代码即可 |

---

## 二、ECS / Docker 推荐步骤（一条命令进容器）

假设代码在 ECS 上（与 Windows 同步后的路径示例）：

```bash
cd ~/project2/miniob
# 或
cd /mnt/c/Users/HUAWEI/Desktop/project2/miniob

# 进入与 Dev Container 相同的构建环境
docker run --rm -it \
  -v "$(pwd):/root/miniob" \
  -w /root/miniob \
  oceanbase/miniob \
  bash
```

在容器内：

```bash
# 1. 编译
bash build.sh debug --make -j$(nproc)

# 2. 运行任务五测试脚本（不依赖 .result 文件）
chmod +x scripts/run_drop_table_test.sh
./scripts/run_drop_table_test.sh
```

看到 `All drop table tests passed.` 即任务五通过。

---

## 三、Dev Container（方式 A）

1. Cursor / VS Code：`Dev Containers: Reopen in Container`
2. 容器终端：

用 Cursor 打开文件夹 `C:\Users\HUAWEI\Desktop\project2\miniob` 后，「在容器中重新打开」。

容器内路径为 `/root/miniob`（见 `.devcontainer/devcontainer.json`）：

```bash
cd /root/miniob
bash build.sh debug --make -j$(nproc)
./scripts/run_drop_table_test.sh
```

---

## 四、WSL2（方式 B）

```bash
sudo apt update
sudo apt install -y build-essential cmake git flex bison python3

cd /mnt/c/Users/HUAWEI/Desktop/project2/miniob
bash build.sh init    # 首次需要拉子模块、编第三方库，较久
bash build.sh debug --make -j$(nproc)
./scripts/run_drop_table_test.sh
```

---

## 五、官方 `miniob_test.py`（可选）

`primary-drop-table` **没有** 预置 `result/primary-drop-table.result`，直接跑会对比失败。

若要使用官方脚本，需先生成基准结果：

```bash
cd test/case
python3 miniob_test.py --test-cases=primary-drop-table --report-only
# 将生成的 result 拷到 result/ 目录后，再去掉 --report-only 再跑
```

更省事：直接用本仓库 **`scripts/run_drop_table_test.sh`**（已内置 SUCCESS/FAILURE 断言）。

---

## 六、集成测试（需 MySQL，可选）

```bash
cd test/integration_test
# 需配置 MySQL，见 integration_test/README.md
python3 libminiob_test.py ...
```

训练营一般用 `primary-drop-table.test` 或本脚本即可。

---

## 七、测试用例与任务五对应关系

| 编号 | 场景 | 期望 |
|------|------|------|
| 1 | 删除空表 | SUCCESS |
| 2 | 删除有数据表 | SUCCESS |
| 3 | 删后 INSERT/SELECT | FAILURE；重建后 SELECT 空 | SUCCESS |
| 4 | 重复 DROP / 删不存在表 | FAILURE |
| 5 | 删后 CREATE 同名 | SUCCESS |
| 6 | 删带索引表后 SELECT | FAILURE |

---

## 八、常见问题

| 现象 | 处理 |
|------|------|
| `observer not found` | 先 `bash build.sh debug --make -j4` |
| `obclient not found` | 同上，确认 `build/bin/obclient` 存在 |
| Docker 拉镜像慢 | `docker pull oceanbase/miniob` |
| Windows 路径挂载 | Docker Desktop 共享盘符，或用 ECS Linux 路径 |
