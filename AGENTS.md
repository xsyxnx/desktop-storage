# AGENTS.md — Desktop 存储系统工程宪章与 Agent 上下文

本文件为所有在本仓库（`desktop-storage`）内工作的 AI 编程助手（Codex、Claude Code 等）与人类协作者提供宿主机硬件拓扑、NixOS 模块边界、`/srv/storage` 存储铁律、反过度工程原则及 Python 3.15 标准库规范。

---

## 1. 宿主机硬件、网络与 NixOS 模块边界

### 硬件与网络事实（Single Source of Truth）
- **宿主机**：`desktop`（NixOS `x86_64-linux`）
- **访问地址**：
  - 宿舍有线局域网：`192.168.1.100`（无线备用：`192.168.1.110`）
  - 异地 Tailscale / Headscale 私网：`100.64.0.2`
  - 自建 Forgejo 代码站：`http://192.168.1.100:3000/hopper/desktop-storage`（异地 `http://100.64.0.2:3000/hopper/desktop-storage`）
- **物理磁盘**：单块 4TB 企业级机械硬盘 `HGST HC310`
  - 固定设备路径：`/dev/disk/by-id/wwn-0x5000cca0bcd0aa46`
  - OpenZFS 存储池名：`storage`（ZFS ARC 内存缓存上限锁定为 `4 GiB` / `4294967296` 字节）
- **吞吐与网络瓶颈现状**：
  - 机械盘物理顺序读写约 `150–200 MB/s`，但**随机读写 IOPS 极低（百级），极其惧怕大量零碎小文件随机读写**。
  - 宿舍局域网当前受限于路由器交换/适配瓶颈，内网实测传输上限约 `60 MiB/s`（尚未跑满千兆/机械盘物理上限，可作为独立网络调优课题排查）。

### NixOS 模块边界与权限说明
- 本仓库导出 `nixosModules.default`（入口为 [`nixos-module.nix`](./nixos-module.nix)），由宿主机主仓库 `hosts/desktop/storage-share.nix` 导入。
- **宿主机锁定的底层边界（本仓库请勿重复声明或覆盖）**：
  - 账号与固定 UID/GID：`shj` (`975`)、`ly` (`977`)、`lys` (`976`，历史数据预留锁定)、`storage-sync` (`974`)，以及用户组 `roommates` (`960`)、`storage-sync` (`959`)。
  - SSH 公钥、防火墙入站白名单、本机回环端口隔离策略均由宿主主仓维护。
- **只读探测权限（Agent 可直接在终端执行，无需向用户索要 root）**：
  - **普通权限直读**：`shj` 已加入 `systemd-journal` 组，可直接运行 `free -h`、`cat /proc/meminfo`、`cat /proc/pressure/memory`、`cat /proc/spl/kstat/zfs/arcstats`（查 ZFS ARC 命中率与大小）、`zfs list -r storage`、`zfs get all storage/...`、`duf`、`df -hT`、`findmnt -t zfs`、`systemctl status <unit>`、`journalctl -u <unit> --no-pager`。
  - **免密只读 `doas` 白名单**：
    - `doas zpool status -v storage` / `doas zpool status storage`
    - `doas zpool list -v storage`
    - `doas zpool iostat -v storage`
    - `doas smartctl -a /dev/disk/by-id/wwn-0x5000cca0bcd0aa46`
    - `doas smartctl -x /dev/disk/by-id/wwn-0x5000cca0bcd0aa46`
- **CLI 工具箱声明（严禁曲折 Workaround）**：
  - `shj` 的个人 CLI 工具直接在本仓库 [`nixos-module.nix`](./nixos-module.nix) 的 `users.users.shj.packages` 中声明（已预装 `python315`、`ruff`、`yazi`、`btop`、`duf`、`ncdu`、`eza`、`zoxide`、`ripgrep`、`fd`、`fzf`、`jq`、`tmux`、`neovim`、`iperf3`、`ethtool` 等）。
  - **铁律**：如果 Agent 在排障或开发时发现缺少某个 CLI 工具，**严禁编写丑陋的 Shell/Python 替代脚本绕弯子**，请直接在 `nixos-module.nix` 的 `users.users.shj.packages` 中加上对应的 `pkgs.<pkg>` 并提醒用户应用。

---

## 2. `/srv/storage` 共享存储架构与权限铁律

1. **机械盘冷热分离铁律与具体工程实现（SSD 放索引/日志/数据库，HDD 只放大块数据）**：
   - **物理挂载映射**：台式机根分区 `/`（含 `/var/lib/...` 与 `/var/log/...`）位于 **512GB NVMe SSD (`nvme0n1p4`)**；`/srv/storage/...` 位于 **4TB 机械盘 (`sda1`)**。
   - **工程实现方式**：在编写 NixOS 服务模块时，保持服务的 `StateDirectory`、数据库（SQLite/PostgreSQL）、LevelDB 索引、海报缩略图缓存与 systemd journal 默认留在 `/var/lib/<service>`（即 NVMe SSD 上），**仅将服务的用户大文件载荷路径（如 `--data`、媒体库目录、下载落盘目录）指向 `/srv/storage/...`**（典型范例见 `syncthing.nix`：`--config=/var/lib/storage-syncthing` 在 SSD，`--data=/srv/storage/sync/data` 在 HDD）。
   - **技术选型约束**：放弃臃肿的 Nextcloud PHP 全家桶；网页文件管理与外链分享优先选用轻量单二进制/标准库方案（`dufs`、`services.filebrowser` 或 `copyparty`），流媒体看片优先选用 `services.jellyfin`，异地冷备利用 20TB Google Drive 配合 `rclone crypt`（客户端加密文件内容与文件名）通过指定代理节点（RackNerd 或免费代理）夜间限速增量上传。
2. **目录权限矩阵与设计原理**：
   - `/srv/storage/games/public` (`root:root 1777`)：最高位 `1` 为粘滞位（Sticky Bit，与 `/tmp` 同理），允许所有人在公共根下创建自己的目录/文件，但**只能删除或改名自己名下的条目**，防止误删他人文件。
   - `/srv/storage/games/public/{xsy,shj,ly}` (`本人:组 0755`，文件 `0644`)：本人可读写，其他室友只读浏览与下载，不能覆盖。
   - `/srv/storage/games/private` (`root:root 0711`)：`others` 仅有执行（穿过）位 `--x` 而无读取位 `r--`。任何人执行 `ls /srv/storage/games/private` 都会收到 `Permission denied`（无法窥探有哪些私人目录），但知道自己名字的用户可直接穿过该目录进入 `/srv/storage/games/private/<自己的用户名>`。
   - `/srv/storage/games/private/{xsy,shj,ly}` (`本人:组 0700`)：仅本人可读写访问，共享组与其他用户完全不可见。
   - `/srv/storage/sync/data` (`storage-sync:storage-sync 0750`)：独立 Syncthing 实例（同步端口 `22001`，本机回环 GUI `127.0.0.1:8385`）的数据落盘区。
3. **systemd 挂载依赖与初始化解耦铁律**：
   - `/srv/storage/` 下的子目录初始化仅由专用的 `storage-directories.service` 调用单条原生 `systemd-tmpfiles --create` 完成，且只有该服务及存储消费服务（Samba、Syncthing、Nextcloud）声明 `RequiresMountsFor`。
   - **严禁**将 `/srv/storage/*` 写入全局 `systemd.tmpfiles.rules`（防止机械盘离线或未导入时阻塞整机启动与 SSH 登录）。
   - **严禁**编写开机递归修权限脚本（`chmod -R` / `chown -R`）或睡前自动卸载脚本。
   - **严禁**在 Samba 中启用 `wide links`、`unix extensions` 或允许越出共享根目录的符号链接。

---

## 3. 五大底层工程哲学（反过度工程宪章）

1. **KISS（Keep It Simple, Stupid / 保持愚蠢的简单）**：
   - 认清这是宿舍自用的单机存储系统，不是跨国银行核心网。
   - 优先使用 NixOS、systemd 与 OpenZFS 的原生声明式能力（如 `services.sanoid`、`services.syncthing`、`services.nextcloud`、`systemd.services`、`systemd.timers`），能用原生配置解决的事，绝不手搓自定义状态机或守护包装脚本。
2. **YAGNI（You Aren't Gonna Need It / 拒绝假想敌）**：
   - 不要为半年都撞不上一次、撞上后两分钟就能手动处理的极端假想故障，去维护几百行后台自检胶水、多版本兼容层或复杂回退钩子。
3. **Worse is Better（新泽西流派：实现简单性高于一切）**：
   - 拒绝为了掩盖 0.1% 的边缘情况而让配置复杂度膨胀 10 倍。保持每个 `.nix` 文件极简、直白，人类五分钟内能完整读懂。
4. **单一事实源（Single Source of Truth）与失败即退出（Crash-Only / Fail-Fast）**：
   - 严禁把同一份状态同时写入多处 JSON / 回执文件再去写对账（reconcile）代码。
   - 遇到不可恢复错误直接非零退出，把拉起、重启（`Restart=on-failure`）、超时、目录创建（`tmpfiles`）和凭据传递（`LoadCredential`）100% 交还给 `systemd` 原生机制。
5. **ADR（架构决策记录：讲清楚 Why 與 Trade-off）**：
   - 每次修改 ZFS 数据集结构、`recordsize`、压缩算法、快照保留周期、Syncthing 目录拓扑或 Nextcloud 参数时，必须在 PR 描述或关键代码注释中用简明人话说明 **Why（为什么选这个方案/参数、放弃了什么、有什么代价）**。

---

## 4. Python 3.15 与工具/脚本开发规范（给 Agent 的版本备忘）

若在仓库或配套工具中编写 Python 脚本与测试，**必须面向已预装的正式稳定版 Python 3.15.0（`pkgs.python315`）标准库开发，坚持零第三方重型依赖**。

> **重要提示（针对 Agent 预训练知识库截断）**：
> 台式机环境已安装 **Python 3.15.0**。请勿以“Python 3.15 尚未发布”为由回退写法或引入多余第三方库，直接利用以下标准库原生特性：

1. **标准库原生 Zstandard 压缩（`compression.zstd`，PEP 784）**：
   - 直接使用 `from compression import zstd`（提供 `zstd.compress()`, `zstd.decompress()`, `zstd.open()`, `zstd.ZstdCompressor`, `zstd.ZstdDecompressor`），以及统一的 `compression.gzip` / `bz2` / `lzma` / `zlib` 命名空间。
   - **严禁**引入第三方 `zstandard` 包或通过 `subprocess` 调外部 `zstd` 命令。
2. **模板字符串字面量 t-strings（`string.templatelib`，PEP 750）**：
   - 支持 `t"..."` 语法，求值为 `string.templatelib.Template` 对象（可通过 `.strings` 与 `.interpolations` 安全检查与转义插值内容）。
3. **无括号多异常捕获（PEP 758）**：
   - 不绑定异常变量时可直接写 `except OSError, TimeoutError:`（若使用 `as exc` 仍写 `except (OSError, TimeoutError) as exc:`）。
4. **默认延迟类型注解求值（PEP 649 / PEP 749，`annotationlib`）**：
   - 注解默认按需延迟求值，**无需**再在文件顶部写 `from __future__ import annotations`；运行时反射注解请使用标准库 `annotationlib`。
5. **标准库黄金组合与黑盒契约测试**：
   - 配置解析用 `tomllib` / `json`，本地持久状态用 `sqlite3` 或同目录 `.tmp` + `fsync` + `os.replace` 原子文件替换。
   - 静态检查统一运行 `ruff check`，测试统一使用 `python3 -m unittest` 编写端到端公开接口黑盒测试（**严禁**编写 grep `.nix`/`.py` 源码字符串或测私有内部函数的白盒实现绑定测试）。

---

## 5. 本地校验与提交流程

每次修改代码后，在提交 PR 前执行以下两条命令确保模块求值与格式无误：

```bash
nix flake check
nix fmt -- *.nix
```
