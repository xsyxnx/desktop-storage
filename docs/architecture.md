# 存储架构、权限设计与技术选型参考

本文件记录 `desktop-storage` 的硬件拓扑、冷热分离工程实现、ZFS/Unix/Samba 经典设计机关以及服务演进基线。

---

## 1. 硬件拓扑与冷热分离工程实现

- **物理磁盘映射**：
  - **系统盘（NVMe SSD）**：台式机根分区 `/`（含 `/var/lib/...` 与 `/var/log/...`）位于 **512GB NVMe SSD (`nvme0n1p4`)**，具备极高的随机读写 IOPS。
  - **共享数据盘（企业级机械盘）**：`/srv/storage/...` 位于单块 **4TB 企业级机械硬盘 `HGST HC310`**（固定设备路径 `/dev/disk/by-id/wwn-0x5000cca0bcd0aa46`），OpenZFS 存储池名为 `storage`（ARC 内存缓存上限锁定为 `4 GiB` / `4294967296` 字节）。
- **吞吐与 IOPS 边界**：
  - 机械盘顺序读写约 `150–200 MB/s`，但**随机读写 IOPS 极低（百级），极其惧怕高频零碎小文件**。
  - **内网 `60 MiB/s` 瓶颈实测破案**：`desktop` 有线网卡 `enp6s0` (`192.168.1.100`) 物理协商为满血 `1000Mb/s Full Duplex`。此前笔记本 (`x1c9`) 实测卡在 `60 MiB/s` 是因为笔记本走的是 5GHz Wi-Fi (`wlp0s20f3`)，使用 `iperf3` 实测单流 TCP 为 `329 Mbps`（约 `40 MiB/s`），4 并发流（`-P 4`）可达 `578–638 Mbps`（约 `68–76 MiB/s`，接近 2x2 Wi-Fi 空口物理极限）。全有线接入的台式机可跑满千兆线速（`940 Mbps` / `112 MiB/s`）。为此 [`../samba.nix`](../samba.nix) 已开启 `server multi channel support = yes`（SMB3 多通道并发）及内核 `arp_ignore=1` / `arp_announce=2`（防止同网段无线网卡 `wlp5s0` 抢答有线 IP 的 ARP 请求）。
- **冷热分离的 NixOS 实现方式**：
  - 编写服务模块时，**不要改动服务的默认状态目录**，让 `StateDirectory`、数据库（SQLite/PostgreSQL）、LevelDB 索引、海报缩略图缓存与 systemd journal 默认留在 `/var/lib/<service>`（即 NVMe SSD 上）。
  - **仅将服务的用户大文件载荷路径**（如 `--data`、媒体库目录、下载落盘目录）指向 `/srv/storage/...`（范例见 [`../syncthing.nix`](../syncthing.nix)：`--config=/var/lib/storage-syncthing` 在 SSD，`--data=/srv/storage/sync/data` 在 HDD）。

---

## 2. 目录权限矩阵与高杠杆存储小机关

### 已落地的底层机关

1. **`/srv/storage/games/public` (`root:root 1777`) — Sticky Bit 防误删公共区**：
   - 最高位 `1` 为粘滞位（`drwxrwxrwt`，与 `/tmp` 同理），允许所有人在公共根下创建目录/文件，但**只能删除或改名自己名下的条目**。
   - `/srv/storage/games/public/{xsy,shj,ly}` (`本人:组 0755`，文件 `0644`)：本人可读写，其他室友只读浏览与下载。
2. **`/srv/storage/games/public/scratch` (`root:root 1777`, `30d` TTL) — 30 天自动焚毁空投区**：
   - 由 `storage-scratch-clean.timer` 每日调用原生 `systemd-tmpfiles --clean` 清理超过 30 天未访问的文件，解决公共网盘常见的“临时大包没人敢删、最终塞满硬盘”痛点。
3. **`/srv/storage/games/private` (`root:root 0711`) — 可穿越不可列表盲盒根目录**：
   - `others` 仅有执行（穿过）位 `--x` 而无读取位 `r--`。任何人执行 `ls /srv/storage/games/private` 都会收到 `Permission denied`（无法窥探有哪些私人目录），但知道自己名字的用户可直接穿过该目录进入 `/srv/storage/games/private/<自己的用户名>`（`0700`，仅本人可读写）。
4. **`storage/ballast` (`mountpoint=none`, `refreservation=200G`) — ZFS 90% 满盘雪崩压舱石**：
   - **原理**：OpenZFS 采用写时复制（CoW）与分片区域（Metaslab）管理空间。当池容量超过 80%–90% 时，大块连续空闲空间枯竭，分配器从首次适应（First-Fit）退化为最佳适应（Best-Fit）扫描，导致严重碎片化与写性能断崖下跌。
   - **实现**：[`../zfs.nix`](../zfs.nix) 中的 `storage-zfs-ballast.service` 声明式确保空数据集 `storage/ballast` 预留 `200G` 物理空间。哪怕池子被写到 `df` 显示 100% 满，ZFS 底层仍握有 200GB 连续物理空闲块作为安全气囊；紧急时刻管理员只需临时调小 `refreservation` 即可瞬间释放空间。
5. **Samba `veto files` — 协议层拦截操作系统垃圾文件**：
   - [`../samba.nix`](../samba.nix) 配置了 `veto files = /Thumbs.db/desktop.ini/.DS_Store/._*/` 与 `delete veto files = yes`，直接从 SMB 协议层阻止 Windows 资源管理器与 macOS Finder 在机械盘里生成成千上万个零碎隐藏元数据小文件，保持目录整洁并节省机械盘随机寻道 IOPS。

### 可由协作者继续扩展的进阶机关

1. **Samba `shadow_copy2` + ZFS 快照 = Windows 原生右键“还原以前的版本”时光机**：
   - 在配置好 `services.sanoid`（按小时/天自动生成 `.zfs/snapshot/` 快照）后，只需在 [`../samba.nix`](../samba.nix) 的共享配置中加入：
     ```nix
     "vfs objects" = "shadow_copy2";
     "shadow:snapdir" = ".zfs/snapshot";
     "shadow:sort" = "desc";
     # 根据 sanoid 快照命名格式匹配，例如 autosnap_%Y-%m-%d_%H:%M:%S_hourly
     "shadow:format" = "autosnap_%Y-%m-%d_%H:%M:%S_hourly";
     "shadow:localtime" = "yes";
     ```
   - 效果：Windows 用户无需登录 SSH，直接在资源管理器里右键任意文件或文件夹 -> **属性 -> 以前的版本（Previous Versions）**，即可直接浏览历史快照并一键还原或拖拽恢复。
2. **Unix `1733` (`drwx-wx-wt`) 个人盲投收件箱（Blind Drop-Box）与 `0711` 免密暗链**：
   - **单向私密收件箱（`1733`）**：当室友之间需要传递含身份证、账单、密钥等不宜放在 `public/scratch` 被第三人看见的文件时，可创建如 `/srv/storage/games/public/xsy/inbox`（`1733 xsy:roommates`）。去掉读权限 `r` 后，任何人可往里丢文件、受粘滞位 `t` 保护谁也删不掉别人的文件，且任何人都无法 `ls` 查看箱内已有文件列表，只有目录主人 `xsy` 能读取全貌。
   - **免密暗链目录（`0711`）**：在 `0711` 目录下放置带随机后缀的文件（如 `secret-8f9a.zip`），由于无法 `ls` 列表，只有得知完整文件名的接收者才能通过完整路径直接拉取文件。

---

## 3. 服务选型与例行巡检基线（Good Defaults）

- **轻量网页文件管理与外链分享**：放弃臃肿的 Nextcloud PHP 全家桶，优先评估单二进制/轻量方案（如 `dufs`、`services.filebrowser`、`copyparty`、`sftpgo` 等）。
- **局域网随手互投（类 AirDrop）**：优先考虑 `PairDrop` 或 `LocalSend`。
- **流媒体影院**：优先选用 `services.jellyfin`（管理 `/srv/storage/media`）。
- **20TB Google Drive 异地加密冷备**：使用 `rclone crypt`（基于成熟的 `XSalsa20 + Poly1305` 标准在本地加密文件内容与文件名）配合 `systemd.timer`，通过外部代理节点（如 RackNerd 或免费代理）夜间限速增量上传。
- **硬盘健康巡检推荐频率**：
  - **每周一次 SMART 短自检**（如周三 `03:00`，耗时约 2 分钟）。
  - **每月一次 ZFS Scrub 全盘校验**（如每月第一个周日 `03:00`）。
  - **每月一次 SMART 长自检**（如每月 15 日 `02:00`，与 Scrub 错开半月避免读写叠加）。
  - 配合 `zed` 与 `smartd` 挂载异常告警通知与每月一次的心跳摘要（Monthly Heartbeat Digest）。
