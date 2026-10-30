{
  config,
  lib,
  pkgs,
  ...
}:
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

  # ZFS 压舱石数据集 (storage/ballast)：预留 200G 物理空间作为满盘安全气囊
  # 防止池容量超过 90% 时 Metaslab 连续空闲块枯竭导致 CoW 写性能断崖下跌与严重碎片化
  # 仅在数据集不存在时创建，避免覆盖管理员在紧急情况下临时调小 refreservation 的操作
  systemd.services.storage-zfs-ballast = {
    description = "Ensure ZFS ballast dataset (200G refreservation airbag) exists";
    after = [ "zfs-import-storage.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.boot.zfs.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "ensure-storage-ballast" ''
        if ! zfs list -H -o name storage >/dev/null 2>&1; then
          exit 0
        fi
        if ! zfs list -H -o name storage/ballast >/dev/null 2>&1; then
          zfs create -o mountpoint=none -o refreservation=200G storage/ballast
        fi
      '';
    };
  };
}
