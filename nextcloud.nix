{ ... }:
{
  # 阶段三待实现：Nextcloud 网盘模块（对应 /srv/storage/cloud）
  #
  # 设计约束提示：
  # 1. 机械盘随机读写 IOPS 极低，因此 PostgreSQL 数据库和 Redis 缓存必须留在系统 SSD（默认 /var/lib/postgresql 与 /var/lib/redis）
  # 2. 只有 Nextcloud 的实际文件存储目录（datadir）挂到机械盘的 /srv/storage/cloud/nextcloud
  # 3. 对应的 systemd 服务需要加上 unitConfig.RequiresMountsFor = [ "/srv/storage/cloud" ]，防止未挂载时写进 SSD
}
