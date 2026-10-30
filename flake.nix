{
  description = "Declarative storage modules for Desktop (OpenZFS mounts, Samba, Syncthing, Nextcloud)";

  inputs = {
    # 与宿主机 nixos-config 保持同源：
    # nixos-unstable-small 仅以核心服务端组件、内核与基础 NixOS 测试作为门禁，
    # 无需等待十万个桌面/GUI 包全部编译通过，既具备官方二进制缓存又比 nixos-unstable 更新更快
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.${system};
      testSystem = lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          (
            { pkgs, ... }:
            {
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };
              networking.hostName = "desktop";
              networking.hostId = "ecb8b63f";
              system.stateVersion = "26.05";
              users.groups = {
                roommates.gid = 960;
                storage-sync.gid = 959;
              };
              users.users = {
                xsy = {
                  isNormalUser = true;
                  uid = 1000;
                };
                shj = {
                  isSystemUser = true;
                  uid = 975;
                  group = "roommates";
                };
                ly = {
                  isSystemUser = true;
                  uid = 977;
                  group = "roommates";
                };
                storage-sync = {
                  isSystemUser = true;
                  uid = 974;
                  group = "storage-sync";
                };
              };
            }
          )
        ];
      };
      cfg = testSystem.config;
    in
    {
      nixosModules.default = import ./nixos-module.nix;
      nixosModules.storage = import ./nixos-module.nix;

      formatter.${system} = pkgs.nixfmt;

      # 1 秒级惰性求值冒烟测试（Smoke Test）：
      # 1. assert 在求值阶段验证核心服务与挂载点未被意外删改；
      # 2. 在 runCommand 中引用 ExecStart 强制触发 Nix 对整个模块树做类型与软件包求值检查，
      #    无需真正编译数 GB 的完整系统镜像即可在 1 秒内完成静态门禁校验
      checks.${system}.eval-check =
        assert cfg.services.samba.enable;
        assert cfg.fileSystems ? "/srv/storage/games";
        assert cfg.fileSystems ? "/srv/storage/cloud";
        assert cfg.fileSystems ? "/srv/storage/sync";
        assert cfg.fileSystems ? "/srv/storage/media";
        assert cfg.systemd.services ? "storage-directories";
        assert cfg.systemd.services ? "storage-zfs-ballast";
        assert cfg.systemd.services ? "storage-syncthing";
        pkgs.runCommand "desktop-storage-eval-check" { } ''
          echo "${cfg.systemd.services.storage-syncthing.serviceConfig.ExecStart}" >/dev/null
          echo "${cfg.systemd.services.storage-directories.serviceConfig.ExecStart}" >/dev/null
          echo "${cfg.systemd.services.storage-zfs-ballast.serviceConfig.ExecStart}" >/dev/null
          touch "$out"
        '';
    };
}
