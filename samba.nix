{ lib, pkgs, ... }:
let
  roommates = [
    "shj"
    "ly"
  ];
  public = "/srv/storage/public";
  private = "/srv/storage/private";
  media = "${public}/media";
  sync = "/srv/storage/sync";
  mounts = [
    public
    private
    "${private}/xsy"
    "${private}/shj"
    "${private}/ly"
    "${private}/xsy/archives/deltachat"
    "${private}/xsy/archives/cold-backups"
    media
    sync
  ];
  storageTmpfilesConf = pkgs.writeText "storage-directories.conf" (
    lib.concatStringsSep "\n" (
      [
        "d ${public} 1777 root root -"
        "d ${public}/scratch 1777 root root 30d"
        "d ${public}/depot 1777 root root -"
        "d ${public}/xsy 0755 xsy roommates -"
        "d ${private} 0711 root root -"
        "d ${private}/xsy 0700 xsy users -"
        "d ${private}/xsy/archives 0700 xsy users -"
        "d ${media} 0755 xsy roommates -"
        "d ${sync}/data 2770 storage-sync roommates -"
      ]
      ++ lib.concatMap (name: [
        "d ${public}/${name} 0755 ${name} roommates -"
        "d ${private}/${name} 0700 ${name} roommates -"
      ]) roommates
    )
    + "\n"
  );
  masks = file: directory: {
    "create mask" = file;
    "force create mode" = file;
    "directory mask" = directory;
    "force directory mode" = directory;
    "read only" = "no";
    "guest ok" = "no";
    "follow symlinks" = "no";
    "wide links" = "no";
    "nt acl support" = "no";
    "store dos attributes" = "no";
    "map archive" = "no";
    "map hidden" = "no";
    "map system" = "no";
    # 从 SMB 协议层直接拦截 Windows/macOS 资源管理器自动生成的缩略图与元数据垃圾文件
    # 避免成千上万个零碎隐藏小文件污染目录并消耗机械盘宝贵的随机寻道 IOPS
    "veto files" = "/Thumbs.db/desktop.ini/.DS_Store/._*/";
    "delete veto files" = "yes";
  };
in
{
  # 仅在对应 ZFS 数据集挂载就绪后初始化目录权限，避免未挂载时误写到根分区 SSD
  # - 1777 (Sticky bit): 公共根允许所有人建目录，但禁止删除或改名别人的文件
  # - 0755: 公共区个人目录本人可写、其他人只读
  # - 0711: 私人区根目录仅允许穿过 (x)，禁止 ls 列出其他人的目录名 (无 r)
  # - 0700: 私人子目录仅本人可读写
  # - 2770 (Setgid): 同步数据目录继承 roommates 组权限，方便组成员与同步服务协作
  systemd.services.storage-directories = {
    description = "Initialize shared storage directories with tmpfiles";
    wantedBy = [ "multi-user.target" ];
    requires = [ "storage-layout-migration.service" ];
    after = [ "storage-layout-migration.service" ];
    unitConfig.RequiresMountsFor = mounts;
    before = [
      "samba-smbd.service"
      "dufs.service"
      "storage-syncthing.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemd-tmpfiles --create ${storageTmpfilesConf}";
    };
  };

  systemd.services.storage-scratch-clean = {
    description = "Evict expired files from /srv/storage/public/scratch (30d TTL)";
    unitConfig.RequiresMountsFor = [ public ];
    requires = [ "storage-directories.service" ];
    after = [ "storage-directories.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemd-tmpfiles --clean ${storageTmpfilesConf}";
    };
  };

  systemd.timers.storage-scratch-clean = {
    description = "Daily cleanup of 30-day expired files in public/scratch";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = false;
    };
  };

  services.samba = {
    enable = true;
    openFirewall = false;
    nmbd.enable = false;
    winbindd.enable = false;
    usershares.enable = false;
    settings = {
      global = {
        "server role" = "standalone server";
        "security" = "user";
        "map to guest" = "Never";
        "valid users" = lib.concatStringsSep " " roommates;
        "interfaces" = "127.0.0.1/32 192.168.1.100/32 192.168.1.110/32";
        "bind interfaces only" = "yes";
        "hosts allow" = "127.0.0.1 192.168.1.0/24";
        "hosts deny" = "ALL";
        "smb ports" = "445";
        "server min protocol" = "SMB2_02";
        # 开启 SMB3 多通道 (Multichannel)：允许 Windows 11 等客户端并发建立多条 TCP 流
        # 榨干多队列/多网卡吞吐，并在有线 (192.168.1.100) 与无线 (192.168.1.110) 间无感故障切换
        "server multi channel support" = "yes";
        "unix extensions" = "no";
        "smb3 unix extensions" = "no";
        "load printers" = "no";
        "disable spoolss" = "yes";
      };
      public = masks "0644" "0755" // {
        path = "${public}";
      };
      private = masks "0600" "0700" // {
        path = "${private}/%u";
      };
    };
  };

  security.wrappers."mount.cifs".enable = lib.mkForce false;

  systemd.services.samba-smbd = {
    requires = [ "storage-directories.service" ];
    after = [ "storage-directories.service" ];
    unitConfig.RequiresMountsFor = [
      "/var/lib/samba"
      public
      private
      "${private}/shj"
      "${private}/ly"
    ];
  };

  networking.firewall.extraInputRules = ''
    iifname { "enp6s0", "wlp5s0" } ip saddr 192.168.1.0/24 ip daddr { 192.168.1.100, 192.168.1.110 } tcp dport 445 accept
  '';
}
