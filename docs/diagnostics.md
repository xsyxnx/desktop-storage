# 宿主机网络、账号边界与只读诊断命令参考

本文件供 Agent 与协作者在 SSH 登录台式机（`desktop`）执行现场状态探测、性能排障或软件试玩时查阅。

---

## 1. 宿主机访问地址与锁定边界

- **宿主机**：`desktop`（NixOS `x86_64-linux`）
- **访问地址**：
  - 宿舍有线局域网：`192.168.1.100`（无线备用：`192.168.1.110`）
  - 异地 Tailscale / Headscale 私网：`100.64.0.2`
  - 局域网 Forgejo 代码站：`http://192.168.1.100:3000/hopper/desktop-storage`（异地 `http://100.64.0.2:3000/hopper/desktop-storage`）
- **宿主机锁定的底层 UID/GID（本仓库请勿重复声明或覆盖）**：
  - 用户：`shj` (`975`)、`ly` (`977`)、`lys` (`976`，历史数据预留锁定)、`storage-sync` (`974`)
  - 用户组：`roommates` (`960`)、`storage-sync` (`959`)
  - SSH 公钥、防火墙入站规则与本机回环隔离策略由宿主机主仓库 `hosts/desktop/storage-share.nix` 统一维护。

---

## 2. 只读探测命令清单（无需索要 root 密码）

### 普通权限直读命令
`shj` 已加入 `systemd-journal` 组，可在终端直接执行：
- **内存与负载**：`free -h`、`cat /proc/meminfo`、`cat /proc/pressure/memory`、`btop`
- **ZFS ARC 缓存命中率与水位**：`cat /proc/spl/kstat/zfs/arcstats`
- **ZFS 数据集与挂载容量**：`zfs list -r storage`、`zfs get all storage/games`、`duf`、`df -hT`、`findmnt -t zfs`
- **服务状态与日志**：`systemctl status <unit>`、`journalctl -u <unit> -n 100 --no-pager`

### 免密只读 `doas` 白名单
宿主机 `security.doas` 已对 `shj` 精确放行以下 6 条只读硬件与存储池诊断命令（参数须严格匹配）：

```bash
doas zpool status -v storage
doas zpool status storage
doas zpool list -v storage
doas zpool iostat -v storage
doas smartctl -a /dev/disk/by-id/wwn-0x5000cca0bcd0aa46
doas smartctl -x /dev/disk/by-id/wwn-0x5000cca0bcd0aa46
```

---

## 3. `nix run` 10 秒零污染软件试玩工作流

宿主机已为 `shj` 开放 `nix-daemon` 权限（`allowed-users`），并在局域网与 Tailscale 防火墙放行了 **`18080–18089` TCP 预览端口段**。
在决定把某个候选服务写进 `.nix` 模块前，可直接用 `nix run` 在这些端口拉起临时实例试玩（按 `Ctrl+C` 即退，零残留）：

```bash
# 例 1：在 18080 端口试玩 FileBrowser
nix run nixpkgs#filebrowser -- -a 0.0.0.0 -p 18080 -r /srv/storage/games/private/shj -d /tmp/shj-fb.db

# 例 2：在 18081 端口试玩 dufs
nix run nixpkgs#dufs -- /srv/storage/games/public -b 0.0.0.0 -p 18081 -A
```
随后直接在浏览器打开 `http://192.168.1.100:18080` 即可体验真机效果。
