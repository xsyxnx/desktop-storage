{ pkgs, ... }:
let
  syncRoot = "/srv/storage/sync";
  dataDir = "${syncRoot}/data";
  stateDir = "${syncRoot}/state";
  guiAddress = "127.0.0.1:8385";
  syncPort = 22001;
  discoveryPort = 21028;

  # 首次启动时初始化独立配置，并将同步端口固定到 22001、发现端口固定到 21028，
  # 避免与宿主机原有的 22000 / 8384 实例产生端口冲突。
  initConfigScript = pkgs.writeShellScript "storage-syncthing-init-config" ''
    set -euo pipefail
    if [ ! -f "${stateDir}/config.xml" ]; then
      ${pkgs.syncthing}/bin/syncthing generate --home="${stateDir}" >/dev/null
    fi
    ${pkgs.python3}/bin/python3 - "${stateDir}/config.xml" <<'PY'
    import sys
    import xml.etree.ElementTree as ET

    path = sys.argv[1]
    tree = ET.parse(path)
    root = tree.getroot()

    options = root.find("options")
    if options is not None:
        for elem in list(options.findall("listenAddress")):
            options.remove(elem)
        for addr in ("tcp://0.0.0.0:${toString syncPort}", "quic://0.0.0.0:${toString syncPort}"):
            el = ET.SubElement(options, "listenAddress")
            el.text = addr
        local_port = options.find("localAnnouncePort")
        if local_port is None:
            local_port = ET.SubElement(options, "localAnnouncePort")
        local_port.text = "${toString discoveryPort}"
        ur = options.find("urAccepted")
        if ur is None:
            ur = ET.SubElement(options, "urAccepted")
        ur.text = "-1"

    defaults = root.find("defaults")
    if defaults is not None:
        folder = defaults.find("folder")
        if folder is not None:
            folder.set("path", "${dataDir}")

    tree.write(path, encoding="utf-8", xml_declaration=True)
    PY
  '';
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
      ExecStartPre = initConfigScript;
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
    iifname "tailscale0" ip saddr 100.64.0.0/10 tcp dport ${toString syncPort} accept
    iifname "tailscale0" ip saddr 100.64.0.0/10 udp dport ${toString syncPort} accept
  '';
}
