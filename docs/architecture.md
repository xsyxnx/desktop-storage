# 存储架构与决策

`zfs.nix` 是所有 `/srv/storage` 挂载的唯一声明源。主仓只负责池硬件、用户身份、防火墙和 host 服务。目录及配额见 [README](../README.md)，一次性状态迁移见 [migration](migration.md)。

公开树与私人树分离，避免将 games 整体改名为 public 后泄露历史私密内容。私有用户使用独立数据集；ly/shj 的 refquota=500G 只限制当前引用的数据，不限制所有快照。xsy 无此配额。所有权继续使用宿主固定 UID/GID，旧身份未退出声明。

media 与两个档案数据集使用 ZFS rename，保留内容和快照。普通目录使用 rsync，原件保留。任务明确批准一条可重试迁移服务以及一次性的媒体 go+rX，完成后以持久标记禁止重放。常规启动不扫描全盘修权限。

挂载保留 legacy，由 NixOS fileSystems 负责。noauto/nofail 避免 migration/local-fs 排序环，消费者的 RequiresMountsFor 仍会拉起它们。池离线只让依赖存储的服务失败，全局 tmpfiles 不访问机械盘。

公共目录采用 1777 粘滞位，个人橱窗 0755，private 父项 0711、私人根 0700。Samba public/private 两个共享通过原生权限实现访问控制，禁用 wide links 和 Unix extensions。SMB3 multichannel 与现有 LAN 绑定保持。

scratch 用原生 tmpfiles 30d 清理。public 启用 atime=on、relatime=on，让近期访问参与年龄判断；media 保持 atime=off，减少媒体读写元数据开销。默认年龄判断也考虑修改和状态时间，因此这是“旧且不再活跃”的清理，不是精确最后访问计时器。

同步载荷在机械盘，配置、索引和证书在 SSD `/var/lib/storage-syncthing`。新 daemon 沿用迁来的现有配置，删除每次启动修补 XML 的 wrapper。Hub、Harmonia 密钥和所有主机日志也留在 SSD。

ballast 的 200G refreservation 提供应急余量；迁移只在缺失时创建，已有人工调整保持。它不保证盘上恰好保留连续 200G 或利用率恒低于 90%。压缩和 recordsize 的改变只影响后续写入。

主仓使用 Beszel 观测，并用原生 smartd/autoScrub 替代旧巡检状态机。快照与 Google Drive 备份仍是待办，单盘冗余元数据不是完整容灾。

宿舍 MT3000 的 AP/STA 共用 5GHz HE80 射频限制无线吞吐。此前实测单流约 40MiB/s、并发约 68–76MiB/s；此背景不构成本次迁移的性能验收结果。
