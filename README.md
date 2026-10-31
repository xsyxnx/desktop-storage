# Desktop storage

本仓导出 `nixosModules.default`，统一管理 desktop 的 ZFS 挂载、Samba 与独立 Syncthing。主仓保留账号 UID/GID、dufs、Harmonia、Beszel 和宿主防火墙。首次部署自动迁移旧布局；不要求先手动创建或改名数据集。当前代码是迁移候选，构建通过不代表实机已迁移。

| 数据集和目录 | 权限或属性 | 用途 |
| --- | --- | --- |
| `storage/public` → `/srv/storage/public` | root:root 1777，recordsize=1M，relatime | 公共树 |
| `public/media` | xsy:roommates 0755，内部一次性 go+rX，atime=off | 原 media 数据集零拷贝迁入 |
| `public/depot`、`public/scratch` | root:root 1777；scratch 原生 30d 清理 | 公共大文件、临时空投 |
| `public/{xsy,shj,ly}` | 本人:roommates 0755 | 个人公开目录 |
| `storage/private` | root:root 0711 | 私人树，可穿越不可列出 |
| `private/xsy` | xsy:users 0700，recordsize=1M | 无 refquota |
| `private/{shj,ly}` | 本人:roommates 0700，recordsize=1M，refquota=500G | 每人独立数据集 |
| `private/xsy/archives/{deltachat,cold-backups,nixos-archive}` | 位于 xsy 的 0700 父目录下 | 三个原数据集零拷贝改名 |
| `private/xsy/archives/legacy-games` | 保留旧数字身份和权限 | library、incoming、隐藏文件及其他历史内容 |
| `storage/sync` | recordsize=128K | 同步载荷；状态留 SSD `/var/lib/storage-syncthing` |
| `storage/ballast` | mountpoint=none，已有 200G reservation 保持 | 满盘应急余量 |

全部活动数据集使用 compression=zstd、copies=1、redundant_metadata=all。修改 recordsize/compression 不会重写旧文件。refquota 不限制所有快照和后代的总空间。200G 预留不是固定 90% 利用率保证。

室友使用 `\\192.168.1.100\public` 和 `\\192.168.1.100\private`，已有 Samba 密码保持。media 位于 public 内，不需多挂一个盘。Samba 继续仅开放 LAN，禁用越界软链。xsy 的只读 WebDAV 由主仓提供。

`storage-layout-migration.service` 在第一次上线时停止旧消费者、移除旧挂载并执行迁移。新挂载用 noauto/nofail 和 service 依赖避免开机排序环；`storage-directories.service` 拉起所有活动挂载，再执行原生 tmpfiles 初始化。初始化不执行过期清理，scratch 每日 timer 的 Persistent=false，避免第一次激活补跑历史清理。

`storage/games`、`storage/build-cache`、`storage/logs`、`storage/cloud` 只退出挂载配置，全部保留。脚本没有 destroy、源文件删除或 rsync --delete。`storage/archives` 空父项也保留。迁移成功只写一个完成标记，后续开机不重复拷贝和递归改权限。错误时保留源和现场。

详细过程、重试边界见 [自动迁移](docs/migration.md)。权限与架构见 [架构](docs/architecture.md)，只读排障见 [诊断](docs/diagnostics.md)。

## 验证

```bash
nix fmt -- *.nix
nix flake check
```

checks 包括模块求值和隔离迁移测试。测试运行真实 rsync、校验和与权限操作，但模拟 ZFS、挂载和 systemd；不会操作真实池，不等价于实机迁移验收。

自动快照、Jellyfin 和 Google Drive 加密备份尚未配置。本仓不声称已经形成 3-2-1 备份。
