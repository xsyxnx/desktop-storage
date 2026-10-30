# AGENTS.md — Desktop 存储系统工程宪章

本仓库（`desktop-storage`）管理宿舍台式机（`desktop`）上 4TB 企业级机械盘（OpenZFS 池 `storage`）的声明式挂载与存储服务。所有 Agent 与协作者在开始工作前必须遵守本宪章。

---

## 1. 模块边界与工具铁律

- **模块入口**：本仓库导出 `nixosModules.default`（入口为 [`nixos-module.nix`](./nixos-module.nix)），由宿主机主仓库 `hosts/desktop/storage-share.nix` 导入。
- **宿主机锁定边界（严禁在本仓库重复声明或覆盖）**：
  - 用户与用户组的固定 UID/GID（`shj=975`, `ly=977`, `lys=976`, `storage-sync=974`, `roommates=960`, `storage-sync=959`）、SSH 授权公钥、底层防火墙与环回隔离策略均由宿主主仓维护。
- **缺工具直接声明，严禁曲折 Workaround**：
  - `shj` 的 CLI 工具箱直接在本仓库 [`nixos-module.nix`](./nixos-module.nix) 的 `users.users.shj.packages` 中声明。
  - 若在开发或排障时发现缺少某个命令行工具，**严禁编写丑陋的 Shell/Python 替代脚本绕弯子**，请直接将 `pkgs.<pkg>` 加入 `users.users.shj.packages` 并提醒用户应用。

---

## 2. 五大底层工程哲学与存储排雷铁律（核心准则）

1. **KISS（Keep It Simple, Stupid / 保持愚蠢的简单）**：
   - 认清这是宿舍 3 人使用的单机存储系统，不是跨国银行核心网。
   - **正面做法**：100% 优先使用 NixOS、systemd 与 OpenZFS 的原生声明式能力（如 `services.sanoid`、`systemd-tmpfiles --clean` 的 `30d` 过期清理、Samba `shadow_copy2` / `veto files`、ZFS `refquota` / `refreservation`）。
   - **反面禁令**：能用一行原生配置解决的事，**严禁**手搓自定义后台轮询脚本、复杂状态机或包装守护进程。
2. **YAGNI（You Aren't Gonna Need It / 拒绝假想敌）**：
   - 不要为半年都撞不上一次、撞上后两分钟就能手动处理的极端假想故障，去编写几百行容灾自检胶水、多版本兼容层或自动回退钩子。只解决当前真实存在的痛点。
3. **Worse is Better（新泽西流派：实现简单性高于一切）**：
   - 拒绝为了掩盖 0.1% 的边缘情况而让配置复杂度膨胀 10 倍。保持每个 `.nix` 文件极简、扁平、直白，确保人类五分钟内能从头到尾读懂全部逻辑。
4. **单一事实源（Single Source of Truth）与失败即退出（Crash-Only / Fail-Fast）**：
   - **严禁**把同一份状态同时写入多处 JSON / 标记文件再去写对账（reconcile）代码。
   - 遇到不可恢复错误直接非零退出，把拉起、重启（`Restart=on-failure`）、超时控制、目录创建（`tmpfiles`）和凭据传递（`LoadCredential`）完全交还给 `systemd` 原生机制。
5. **ADR（架构决策记录：讲清楚 Why 与 Trade-off）**：
   - 每次修改 ZFS 数据集结构、`recordsize`、压缩算法、快照策略、同步拓扑或引入新服务时，必须在 PR 描述或关键注释中用简明人话说明 **Why（为什么选它、放弃了什么、有什么代价）**。
6. **四条不可触碰的存储排雷红线**：
   - **冷热分离铁律**：机械盘随机读写 IOPS 极低。所有服务的 `StateDirectory`、数据库（SQLite/PostgreSQL）、索引、缩略图缓存与日志**必须留在系统 NVMe SSD（`/var/lib/<service>`）**，**仅将大文件载荷目录指向机械盘（`/srv/storage/...`）**。
   - **禁止阻塞开机**：`/srv/storage/*` 的目录初始化仅允许放在绑定了 `RequiresMountsFor` 的专用 `storage-directories.service` 中，**严禁写入全局 `systemd.tmpfiles.rules`**（防止机械盘离线时卡死整机开机与 SSH）。
   - **禁止暴利扫盘**：**严禁**编写开机递归修权限脚本（`chmod -R` / `chown -R`）或定时自动卸载脚本。
   - **禁止越界软链**：**严禁**在 Samba 中启用 `wide links`、`unix extensions` 或允许越出共享根目录的符号链接。

---

## 3. 本地校验与提交门禁

每次修改代码后，在提交 Commit 或提 PR 前必须在仓库根目录执行并通过以下两条检查：

```bash
nix flake check
nix fmt -- *.nix
```

---

## 4. 按工作查文档（渐进式加载索引）

为保持上下文精简，具体领域的详细参数与命令请按当前任务需要读取对应文档，无需在无关任务中加载：

- **修改存储目录权限、Samba/ZFS/Syncthing 配置或选型新服务前**：阅读 [`docs/architecture.md`](./docs/architecture.md) 与 [`README.md`](./README.md)。
- **在台式机 SSH 现场排查硬件、ZFS 状态、跑免密 `doas` 诊断或用 `nix run` 试玩软件前**：阅读 [`docs/diagnostics.md`](./docs/diagnostics.md)。
- **编写或修改 Python 脚本与单元测试前**：阅读 [`docs/python-315.md`](./docs/python-315.md)（台式机使用正式版 **Python 3.15.0** 标准库）。
