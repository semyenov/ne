{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/base.nix
    ../../profiles/desktop-gnome.nix
    ../../profiles/nvidia.nix
    ../../profiles/docker.nix
    ../../profiles/security-hardened.nix
    ../../profiles/system-optimizations.nix
  ];

  # Boot loader configuration
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 5;
    efi.canTouchEfiVariables = true;
    timeout = 3;
  };

  # Networking
  networking = {
    hostName = "nixos";
    firewall.enable = true;
  };

  time.timeZone = "UTC";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  console = { font = "Lat2-Terminus16"; useXkbConfig = true; };

  # User accounts
  users.groups.semyenov = {
    gid = 1000;
  };

  users.users.semyenov = {
    isNormalUser = true;
    uid = 1000;
    group = "semyenov";
    home = "/home/semyenov";
    description = "Alexander Semyenov";
    extraGroups = [
      "wheel"         # Enable 'sudo'
      "networkmanager"
      "audio"
      "video"
      "docker"
      "libvirtd"
    ];
    shell = pkgs.fish; # Fish as default shell
  };

  # Shell aliases
  environment.shellAliases = {
    # Modern replacements for core utils
    ll = "lsd -l";
    la = "lsd -la";
    l = "lsd -l";
    ls = "lsd";
    cat = "bat";
    grep = "rg";
    find = "fd";
    sed = "sd";
    du = "dust";
    df = "duf";
    ps = "procs";
    top = "btm";
    htop = "btm";
    dig = "dog";
    
    # Git aliases
    g = "git";
    gg = "gitui";
    lg = "lazygit";
    
    # Quick commands
    j = "just";
    h = "hyperfine";
    
    # NixOS aliases
    rebuild = "sudo nixos-rebuild switch --flake .#nixos";
    update = "nix flake update";
    clean = "sudo nix-collect-garbage -d";
    generations = "sudo nix-env --list-generations --profile /nix/var/nix/profiles/system";
  };

  # System state version
  system.stateVersion = "25.05";
}