# 自动迁移与重试

首次部署由 `storage-layout-migration.service` 自动完成迁移。用户不用手动盘点、创建数据集、执行 rename、rsync 或媒体 chmod。此服务是本任务明确批准的一次性命令式迁移例外；常规挂载和目录仍使用 NixOS/systemd 原生配置。

迁移先等待池导入和系统文件系统就绪，然后停止运行中的 Samba、dufs、storage-syncthing、scratch 清理及 xsy 的 DeltaChat 服务。它正常卸载旧挂载；如果未识别的进程仍占用目录，umount 报错，服务停止，不强卸载、不杀未知进程。

脚本在 root 独占的 `/run/desktop-storage-migration` 下挂载迁移源和目标。games/sync 源以只读方式挂载。第一次运行拒绝已有 public/private 目标和非空 SSD Syncthing 目标，避免覆盖其他工作留下的独特数据。started-v1 记录这些目标随后归本迁移管理；未完成时新消费者一直等待，故重试可覆盖上次不完整副本。

复制使用 `rsync -aHAX --numeric-ids`，保留数字所有权、模式、ACL、xattr 和同一次复制内的硬链接。随后执行 checksum dry-run 并要求没有差异。跨私人数据集的原硬链接会成为独立副本；原 games 数据集仍保留原关系。

已知 xsy/shj/ly 私有目录分别迁入其新数据集。其余 games 内容进入 xsy 的 `archives/legacy-games`，包括旧 library、incoming、未知私人账号、测试文件和隐藏文件。旧 lys 不自动变为 ly。存在目标保留名冲突或异常入口软链时脚本报错，不能用自动覆盖掩盖冲突。

media、deltachat、cold-backups、logs 原位改名。重试只接受旧名存在/新名不存在，或旧名不存在/新名存在；两个名字同时存在时停止。媒体内部一次性执行 go+rX，不跟随软链，不跨文件系统。该操作公开现有媒体的读权限，保留原所有权与写权限。

Syncthing 将旧 state 全量复制到 SSD，保留原 config.xml、证书和数据库。新服务直接加载该配置，不再每次启动修改 XML。迁移要求旧 config.xml 存在；它针对已有 desktop 实例，不是空池/新机器的初始化器。端口 22001、GUI 127.0.0.1:8385、发现端口 21028 沿用原配置。

所有复制校验、属性设置和卸载成功后，脚本同步文件系统并写入 `/var/lib/desktop-storage-migration/complete-v1`。随后排队启动消费者并恢复已配置的 DeltaChat 用户服务，目录服务设置终态根目录权限。
私人根目录在迁移阶段已先封闭为 0700，避免最终挂载与 tmpfiles 之间出现暴露窗口。
Home Manager 不依赖 HDD，用户登录不会等待整盘复制。服务数据和缓存均待在 SSD。该标记只表示数据步骤完成，不表示网络、客户端或服务业务验收通过。

服务失败时保留临时挂载和标记；普通退出会尝试卸载自身挂载，强制中断后的精确同源挂载可由重试接管。RuntimeDirectoryPreserve 避免 systemd 删除尚含挂载的临时目录。下一次启动未完成服务会继续。**完成后不要删除 complete-v1 重放旧源**，否则可能覆盖迁移后的新文件。

只读观察：

```bash
systemctl status storage-layout-migration storage-directories
journalctl -u storage-layout-migration --no-pager
zfs list -r storage
findmnt -t zfs
```

发现真实冲突后先处理明确对象，再重试服务；不提供失败时自动回滚、删数据或重建池的兜底。旧 games/build-cache/logs/cloud、快照和旧 Syncthing state 均不删除。回退代码不能自动撤销 dataset rename，回退时还要保护新树已产生的数据。
