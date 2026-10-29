{ lib, ... }:
let
  # 共享机械盘存储池 (storage) 下由本仓库接管的业务数据集
  # 实际物理盘为 4TB HGST HC310 企业级机械盘：
  # - 顺序读写约 150-200 MB/s，适合大文件与归档
  # - 随机读写 IOPS 较低，频繁随机小文件（如数据库、缓存）应留在系统 SSD
  datasets = [
    "games"
    "build-cache"
    "logs"
    "cloud"
    "sync"
    "media"
  ];
in
{
  # 限制 ZFS ARC 内存缓存上限为 4 GiB，避免吃满宿主机内存
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=4294967296
  '';

  # 将 storage/<dataset> 声明式挂载到 /srv/storage/<dataset>
  # 设置 nofail 与 30s 超时，防止机械盘维护或离线时卡死系统开机流程
  fileSystems = lib.listToAttrs (
    map (dataset: {
      name = "/srv/storage/${dataset}";
      value = {
        device = "storage/${dataset}";
        fsType = "zfs";
        neededForBoot = false;
        options = [
          "nofail"
          "x-systemd.mount-timeout=30s"
        ];
      };
    }) datasets
  );

  systemd.services.zfs-import-storage.serviceConfig.TimeoutStartSec = "90s";
}
