{ lib, ... }:
let
  datasets = [
    "public"
    "public/media"
    "private"
    "private/xsy"
    "private/shj"
    "private/ly"
    "private/xsy/archives/deltachat"
    "private/xsy/archives/cold-backups"
    "private/xsy/archives/nixos-archive"
    "sync"
  ];
in
{
  imports = [ ./migration.nix ];
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=4294967296
  '';
  # Consumers pull mounts AFTER migration; noauto avoids a local-fs cycle.
  fileSystems = lib.listToAttrs (
    map (dataset: {
      name = "/srv/storage/${dataset}";
      value = {
        device = "storage/${dataset}";
        fsType = "zfs";
        neededForBoot = false;
        options = [
          "noauto"
          "nofail"
          "x-systemd.mount-timeout=30s"
          "x-systemd.requires=storage-layout-migration.service"
        ];
      };
    }) datasets
  );
  systemd.services.zfs-import-storage.serviceConfig.TimeoutStartSec = "90s";
}
