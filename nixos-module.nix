{ pkgs, ... }:
{
  imports = [
    ./zfs.nix
    ./samba.nix
    ./syncthing.nix
  ];

  # CLI toolkit for shj on desktop. Add any needed tools from nixpkgs here
  # instead of writing shell/python workarounds.
  users.users.shj.packages = with pkgs; [
    bat
    btop
    curl
    duf
    ethtool
    eza
    fd
    file
    fzf
    git
    htop
    iperf3
    jq
    ncdu
    neovim
    python315
    ripgrep
    ruff
    starship
    tmux
    tree
    wget
    yazi
    zoxide
  ];
}
