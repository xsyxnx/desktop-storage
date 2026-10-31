{ config, pkgs, ... }:
{
  # User-approved one-time migration. No PrivateTmp/PrivateMounts: unmounts
  # must reach the host namespace. No deletion of sources or old datasets.
  systemd.services.storage-layout-migration = {
    description = "Migrate the legacy storage tree without deleting sources";
    requires = [ "zfs-import-storage.service" ];
    after = [
      "local-fs.target"
      "zfs-import-storage.service"
    ];
    before = [ "storage-directories.service" ];
    path = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
      pkgs.rsync
      pkgs.systemd
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "desktop-storage-migration";
      StateDirectoryMode = "0755";
      RuntimeDirectory = "desktop-storage-migration";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = true;
      UMask = "0077";
      TimeoutStartSec = "infinity";
      ExecStart = "${pkgs.bash}/bin/bash ${./migrate-layout.sh}";
    };
    restartIfChanged = false;
  };
}
