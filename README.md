# Desktop 机械盘存储系统指南

这份仓库专门管理宿舍台式机（`desktop`，局域网地址 `192.168.1.100`，异地 Tailscale 地址 `100.64.0.2`）上那块 4TB 企业级机械硬盘（HGST HC310）的存储与共享服务。宿主机底层的其它复杂配置已经全部剥离，这里只保留最干净的 5 个 `.nix` 文件。

> **最省力的上手姿势（强烈建议）**：
> 不用自己死记硬背 Linux 命令或从头硬啃语法。直接 SSH 登到台式机把本仓库 Clone 下来，**在仓库目录里启动你的 AI Agent（如 Codex）**。仓库根目录已经内置了 [`AGENTS.md`](./AGENTS.md)（里面写好了机器硬件参数、NixOS 模块边界、存储铁律和 Python 3.15 规范），你的 Agent 一启动就会自动读懂全貌，你可以直接用自然语言让它帮你跑探测命令、解释配置或改代码。

---

## 零、我们要做成什么样（项目目标与“许愿池”）

我们希望把这块 4TB 机械盘打造成宿舍日常最好用的数字底座。具体来说，就是解决下面这几个肉眼可见的实际需求：
- **大文件局域网高速直传与 Steam 游戏冷车库**：几百 GB 的游戏包、电影、数据集在宿舍内网随手挂载读写。特别是 **Steam 几个月不玩的大作**，完全没必要删掉以后重下——既可以利用 **Steam 原生内置的“局域网游戏传输（Local Network Game Transfer）”**（一人下载，全宿舍 Windows/Linux 自动走内网秒拉），也可以把暂时不玩的游戏备份或移到台式机机械盘“冷车库”存着，想玩时 10 分钟移回本地 SSD（目前内网路由器路径实测只有 `60 MiB/s` 左右，还没跑满机械盘 `150–200 MB/s` 的物理上限，如果你对网络调优感兴趣，这也是个现成的排查坑位）。
- **多设备无感同步 + 局域网类 AirDrop 随手互投**：
  - **持续双向同步（Syncthing）**：适合笔记库、密码库、课程作业、独立游戏存档等需要多端实时保持一致的文件夹。
  - **临时点对点空投（类 AirDrop）**：手机拍张图、截个屏或临时传个包给电脑/舍友，用 Syncthing 会很别扭；我们可以额外部署一个纯网页端的 **PairDrop**（打开局域网网页就能像 AirDrop 一样跨系统投文件和剪切板）或配合 **LocalSend**。
- **手滑误删能自救**：配好 OpenZFS 自动快照后，哪怕不小心删空了目录或把存档改崩了，直接进 `.zfs/snapshot` 历史目录就能把几小时前或几天前的文件拖回来，不用求人恢复。
- **现代网页网盘体验**：补齐 Samba 只能局域网挂盘的短板，有网页端预览、外链分享、手机自动备份能力。

### 关于“许愿”：你也完全可以定义我们要玩什么
平时用电脑、手机时，很多痛点我们习惯了“忍忍算了”，往往是因为不知道开源世界里早就有了现成的好轮子。
非常建议你空了去逛逛 **[Awesome-Selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted)**、**[NixOS 软件包搜索 (search.nixos.org)](https://search.nixos.org/packages)** 或 Linux 社区，看看别人都在自建服务器上玩什么——比如：
- 想不想搭个 **Immich** 自动无损备份手机相册（还带本地 AI 搜图）？
- 想不想搭个 **Jellyfin** 把影音目录变成支持手机/平板直接串流的私人影院？
- 想不想在台式机挂个 **qBittorrent / aria2** 做 24 小时脱机下载并自动归档？
- 或者你平时写代码、管理资料、打游戏时有任何“要是能自动……就好了”的念头，都尽管提出来。**挖掘自己的真实需求、知道计算机世界有什么好东西可以拿来用，比单纯敲几行配置更有意思。**

---

## 一、核心折腾方向（三大主线）

1. **OpenZFS 数据集路径重构、参数调优与健康巡检（[`zfs.nix`](./zfs.nix)）**
   - **现状**：目前公共区和三个人的私人区还混在同一个 `storage/games` 数据集里（导致私人目录的小文件也被迫跟着按 `recordsize=1M`、`copies=1` 存储，且没法单独给私人目录打快照或设配额），自动快照与告警也尚未配置。
   - **你可以做的事**：
     - **数据集解耦重构**：调研将公共大文件区（`storage/public`，`recordsize=1M, copies=1`）与个人私密数据集（`storage/users/{xsy,shj,ly}`，`recordsize=128K, copies=2` 本地双副本防物理坏道，配合 `refquota` 配额）物理拆开的方案。
     - **自动快照与“删库跑路”红蓝对抗演练**：配置每日/每周快照保留策略（如 `services.sanoid` 或 `services.zfs.autoSnapshot`），上线后我们一起做一次 5 分钟的**红蓝对抗实战测试**——故意往目录塞个文件、打快照、当面 `rm -rf` 删空，然后验证你在不借助 `root` 权限的情况下直接进 `.zfs/snapshot` 历史目录把文件完好无损拖回来。
     - **硬盘健康巡检与通知（推荐 Good Default）**：对于企业级机械盘，推荐配置**每周一次 SMART 短自检**（如周三凌晨 3 点，约 2 分钟）、**每月一次 ZFS Scrub 数据块校验**（如每月第一个周日凌晨 3 点）、**每月一次 SMART 长自检**（如每月 15 日凌晨 2 点，与 Scrub 错开两周），并挂载异常告警通知给两位管理员。请在 PR 中附上简短的 **ADR（架构决策说明：为什么这么选、权衡了什么代价）**。

2. **Syncthing 持久同步 + 局域网类 AirDrop 投送设计（[`syncthing.nix`](./syncthing.nix)）**
   - **现状**：独立实例 `storage-syncthing` 已经跑在 `/srv/storage/sync` 上（同步端口 `22001`，Web 管理端 `127.0.0.1:8385`），但具体怎么给大家用还没定型，且缺少随手空投临时文件的工具。
   - **你可以做的事**：构思 Syncthing 的长期共享目录拓扑（如多端存档同步、共享资料库）与防误删版本控制策略（Trashcan / Staggered）；同时调研部署 **PairDrop**（或其它局域网 AirDrop 方案），解决手机与电脑间随手甩临时文件和文本的痛点。

3. **网页文件分享选型 + Jellyfin 影音串流 + 20TB Google Drive 异地加密冷备**
   - **现状**：经过评估，我们决定**放弃臃肿的 PHP 全家桶 Nextcloud**（杀鸡焉用牛刀，且浪费内存），拆解为真正高频的三个具体方向：
     1. **随手网页看文件、上传与发直链（开放选型）**：目前候选有 `dufs`（Rust 极简）、`FileBrowser`（Go 单二进制，带多账号与一键分享短链）、`copyparty`（Python 全能文件服），但**开源界说不定还有更惊艳、更趁手的轮子**（比如 `SFTPGo`、`OpenList/AList` 或其它新兴项目）——非常鼓励你自己在 GitHub、`Awesome-Selfhosted` 和 `search.nixos.org` 上搜寻对比一轮，挑出你觉得最爽的方案写进 ADR！
     2. **电脑、手机、平板直接看片**：用 `services.jellyfin` 把 `/srv/storage/media` 变成局域网/Tailnet 流媒体影院（支持海报墙刮削、跨设备续播、显卡硬解转码）。
     3. **20TB Google Drive 自动化异地加密冷备**：我们手头有 Google AI Ultra 的 20TB 网盘空间，可配合 `rclone crypt`（基于成熟的 `XSalsa20 + Poly1305` 标准在本地把文件内容和文件名全加密后再上传）+ `systemd.timer` + 外部代理节点（如 RackNerd 或白嫖代理，避免占主力线路）实现夜间自动限速增量备份。
   - **冷热分离的工程实现方法（必看）**：
     台式机的根分区 `/`（含 `/var/lib/...` 和 `/var/log/...`）物理上挂在 **512GB NVMe 固态硬盘（`nvme0n1p4`）** 上，而 `/srv/storage/...` 物理上挂在 **4TB 机械硬盘（`sda1`）** 上。
     因此在 NixOS 里实现“索引/日志放 SSD、大文件放机械盘”非常简单：**不要改服务的默认状态目录**（让服务的 `StateDirectory` / 数据库 / 缩略图缓存 / 日志默认留在 `/var/lib/<服务名>`，自动享受 NVMe SSD 的高 IOPS），只在配置里把**真正存大文件的媒体库或数据目录**指到 `/srv/storage/...` 即可（参考 [`syncthing.nix`](./syncthing.nix) 里 `--config=/var/lib/storage-syncthing` 在 SSD、而 `--data=/srv/storage/sync/data` 在机械盘的写法）。

---

## 二、一页纸摸清机器现状与核心设计

### 1. Nix 与 NixOS 是什么？（30 秒建立直觉）
别被 `.nix` 后缀吓到——你可以把 NixOS 理解成**“把整台 Linux 服务器的配置写成了声明式代码”**。
传统 Linux 配服务要到处手敲命令改 `/etc` 下的散装文件，改乱了连自己都忘了动过哪；而在 NixOS 里，建什么目录、装什么软件、跑什么服务全写在这几个 `.nix` 文件里。提交代码部署后系统就自动长成代码描述的样子，而且每次更新都会生成一个独立的系统世代（Generation），改崩了一键就能回滚到上一版，所以尽管放心折腾。

### 2. 硬件底线与冷热分离铁律
- **磁盘参数**：4TB 企业级机械盘 `HGST HC310`（设备路径 `/dev/disk/by-id/wwn-0x5000cca0bcd0aa46`），OpenZFS 存储池名为 `storage`，ZFS ARC 内存缓存上限为 `4 GiB`。
- **冷热分离铁律**：机械盘顺序读写有 `150–200 MB/s`，但**随机读写 IOPS 极低，极其怕高频零碎小文件**。因此：
  - 凡是数据库（PostgreSQL / SQLite）、Redis 缓存、高频索引小文件，**一律留在台式机系统 SSD（`/var/lib/...`）**。
  - 只有大体积的用户数据目录（`/srv/storage/games`、`/srv/storage/sync/data`、`/srv/storage/cloud`）才落到这块机械盘上。

### 3. 代码文件与权限设计全景表

| 文件 / 目录 | 作用与权限设计揭秘 |
| --- | --- |
| [`nixos-module.nix`](./nixos-module.nix) | 仓库总入口，同时声明了你在台式机上的个人 CLI 工具箱（`users.users.shj.packages`）。 |
| [`zfs.nix`](./zfs.nix) | 声明 `storage` 池下各数据集在 `/srv/storage/` 的挂载点及 4 GiB ARC 内存上限。 |
| [`samba.nix`](./samba.nix) | 声明局域网 SMB 共享盘（`\\192.168.1.100\public` 与 `private`）及 `storage-directories.service` 目录初始化。 |
| [`syncthing.nix`](./syncthing.nix) | 跑在 `/srv/storage/sync` 的独立 Syncthing 实例（端口 `22001`，本地管理端 `127.0.0.1:8385`）。 |
| [`nextcloud.nix`](./nextcloud.nix) | 留给你实现的 `/srv/storage/cloud` Nextcloud 模块入口。 |
| `/srv/storage/games/public` (`1777`) | **为什么是 `1777`（`drwxrwxrwt`）？** 最高位 `1` 是粘滞位（Sticky Bit），所有人都可以在公共区建文件，但**只能删除或改名自己建的文件**，防手滑误删室友的东西；个人子目录 `0755` 实现“本人读写、别人只读”。 |
| `/srv/storage/games/public/scratch` (`1777`, `30d`) | **30 天自动焚毁的临时空投区**：由 `systemd-tmpfiles` 原生 `30d` 策略托管，凡是临时给室友传的大包、不确定留多久的文件全扔这里，超过 30 天未访问自动静默清理，避免公共盘沦为没人敢删的陈年垃圾场。 |
| `/srv/storage/games/private` (`0711`) | **为什么是 `0711`（`drwx--x--x`）？** 对其他人只有执行（穿过）位 `x` 没有读取位 `r`。任何人敲 `ls /srv/storage/games/private` 都会被拒绝（没法偷看有哪些私人目录），但知道自己名字就能直接 `cd /srv/storage/games/private/shj` 进自己的 `0700` 私密空间。 |

---

## 三、上手实操三步走

### 第一步：SSH 登机，用现成工具和 Agent 摸清环境

你的 SSH 公钥已经配好，在宿舍局域网内直接终端登录（异地 Tailscale `100.64.0.2` 服务端也已就绪，等你哪天有空修好 Windows 上的 Tailscale 客户端就能在外网连，目前在宿舍直接连局域网 IP 即可）：

```bash
ssh shj@192.168.1.100
```

**已为你配齐的现代 CLI 环境与权限**：
- **顺手的现代命令行工具**：直接用 `yazi`（终端可视化文件管理器）、`duf`（彩色看磁盘挂载与剩余空间）、`ncdu`（扫目录体积占用）、`btop`（看 CPU/内存/磁盘实时吞吐）、`eza -la`（现代版 `ls`）、`zoxide`（快速跳目录）、`ripgrep` (`rg`)、`fd`、`fzf`、`tmux`、`neovim`、`iperf3`（内网测速）。
- **最新 Python 3.15 与代码检查**：已预装正式版 **`python3` (3.15.0)** 与 `ruff`。
- **缺什么工具直接加，别让 Agent 绕弯子**：如果你或你的 Codex 发现缺了什么命令行工具，**千万别让 Agent 写奇葩脚本凑合**，直接在 [`nixos-module.nix`](./nixos-module.nix) 的 `users.users.shj.packages` 里加上包名就行。
- **全套只读探测权限已开放**：
  - 查内存、CPU、ZFS 缓存与系统日志无需 sudo：直接跑 `free -h`、`btop`、`zfs list -r storage`、`zfs get all storage/games`、`systemctl status storage-syncthing.service`、`journalctl -u storage-syncthing.service -n 50`。
  - 查底层 ZFS 存储池健康度与机械盘 SMART 物理体检已配好免密 `doas`：
    ```bash
    doas zpool status -v storage
    doas zpool iostat -v storage
    doas smartctl -a /dev/disk/by-id/wwn-0x5000cca0bcd0aa46
    ```
  - **偷懒秘诀**：把本仓库 Clone 到台式机 `/home/shj/desktop-storage` 后，直接在目录里启动你的 AI Agent，跟它说：“帮我跑一下机器上的 ZFS、挂载和硬盘体检命令，对照当前仓库的 `.nix` 文件给我讲讲现在是怎么跑的”。

### 第二步：把现有服务挂上体验，整理你的想法

1. **体验 Samba 共享盘与测速**：在 Windows 资源管理器连 `\\192.168.1.100\public` 和 `\\192.168.1.100\private`，传个大文件试试速度（顺便看看为什么卡在 `60 MiB/s` 左右）。
2. **用 SSH 隧道打开独立 Syncthing 界面**：
   因为管理界面只绑了本机回环 `127.0.0.1:8385`，在**你自己的电脑终端**跑一条端口转发：
   ```bash
   ssh -N -L 8385:127.0.0.1:8385 shj@192.168.1.100
   ```
   然后在你电脑浏览器打开 `http://127.0.0.1:8385`，把你的手机或电脑 Syncthing 客户端连上去（同步端口 `22001`）试传几个文件。

### 第三步：用 `nix run` 零成本试玩新软件，再改代码提 PR

1. **10 秒极速试玩候选软件（无需写模块、无需等部署）**：
   因为你的主力机是 Windows，我们已经为你开通了台式机 `nix-daemon` 权限，并专门在台式机局域网防火墙放行了 **`18080–18089` 试玩端口段**。
   当你想体验某个开源软件（比如 `filebrowser`、`copyparty`、`dufs` 等）时，不用先写复杂的 NixOS 模块，直接在台式机 SSH 里跑一条 `nix run` 就能在浏览器 `http://192.168.1.100:18080` 看真机效果：
   ```bash
   # 例：10 秒拉起 FileBrowser 试玩界面（按 Ctrl+C 随时退出）
   nix run nixpkgs#filebrowser -- -a 0.0.0.0 -p 18080 -r /srv/storage/games/private/shj -d /tmp/shj-fb.db
   ```
2. **正式定稿写配置与本地自检**：
   挑中满意的软件后，打开局域网代码站 `http://192.168.1.100:3000/hopper/desktop-storage` 把仓库 Clone 到 `/home/shj/desktop-storage`，让你的 AI Agent 结合 [`AGENTS.md`](./AGENTS.md) 帮你写进 `.nix` 模块，然后在台式机 SSH 里直接跑静态检查：
   ```bash
   nix flake check
   nix fmt -- *.nix
   ```
3. 提交 Commit 并在 Forgejo (`http://192.168.1.100:3000`) 上提 Pull Request（别忘了在 PR 里简单写一下你的 **ADR 决策理由**），合并后跑一条 `sys-apply desktop` 即可上线生效。

---

## 四、延伸阅读与灵感库（按需翻阅）

- **开源自建好玩项目大全（找许愿灵感）**：[Awesome-Selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted)
- **NixOS 软件包与模块配置搜索**：[search.nixos.org/options](https://search.nixos.org/options)
- **NixOS 与 Flakes 新手小册子**：[nixos-and-flakes.thiscute.world/zh](https://nixos-and-flakes.thiscute.world/zh/)
- **Linux 命令行与 SSH 隧道基础**：[MIT Missing Semester 中文版](https://missing-semester-cn.github.io/)
- **OpenZFS 核心概念科普（池、数据集、CoW、recordsize）**：搜索 *Ars Technica ZFS 101 (Jim Salter)*
