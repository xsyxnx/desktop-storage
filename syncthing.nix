{ pkgs, ... }:
let
  syncRoot = "/srv/storage/sync";
  dataDir = "${syncRoot}/data";
  stateDir = "/var/lib/storage-syncthing";
  guiAddress = "127.0.0.1:8385";
  syncPort = 22001;
  discoveryPort = 21028;

in
{
  systemd.services.storage-syncthing = {
    description = "Dedicated Syncthing instance for /srv/storage/sync";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [ "storage-directories.service" ];
    after = [
      "network-online.target"
      "storage-directories.service"
    ];
    unitConfig.RequiresMountsFor = [ syncRoot ];
    environment = {
      HOME = dataDir;
      STNOUPGRADE = "1";
    };
    serviceConfig = {
      User = "storage-sync";
      Group = "roommates";
      UMask = "0007";
      StateDirectory = "storage-syncthing";
      StateDirectoryMode = "0700";
      ExecStart = "${pkgs.syncthing}/bin/syncthing serve --no-browser --no-restart --home=${stateDir} --gui-address=${guiAddress}";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [
        dataDir
        stateDir
      ];
    };
  };

  networking.firewall.extraInputRules = ''
    iifname { "enp6s0", "wlp5s0" } ip saddr 192.168.1.0/24 tcp dport ${toString syncPort} accept
    iifname { "enp6s0", "wlp5s0" } ip saddr 192.168.1.0/24 udp dport { ${toString syncPort}, ${toString discoveryPort} } accept
    iifname { "tailscale0", "easytier0" } tcp dport ${toString syncPort} accept
    iifname { "tailscale0", "easytier0" } udp dport ${toString syncPort} accept
  '';
}
