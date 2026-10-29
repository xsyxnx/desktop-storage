{
  description = "Declarative storage modules for Desktop (OpenZFS mounts, Samba, Syncthing, Nextcloud)";

  inputs = {
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

      checks.${system}.eval-check =
        assert cfg.services.samba.enable;
        assert cfg.fileSystems ? "/srv/storage/games";
        assert cfg.fileSystems ? "/srv/storage/cloud";
        assert cfg.fileSystems ? "/srv/storage/sync";
        assert cfg.fileSystems ? "/srv/storage/media";
        assert cfg.systemd.services ? "storage-directories";
        assert cfg.systemd.services ? "storage-syncthing";
        pkgs.runCommand "desktop-storage-eval-check" { } ''
          echo "${cfg.systemd.services.storage-syncthing.serviceConfig.ExecStart}" >/dev/null
          echo "${cfg.systemd.services.storage-directories.serviceConfig.ExecStart}" >/dev/null
          touch "$out"
        '';
    };
}
