{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../minimal.nix  # Base configuration for all users
    ../profiles/common.nix
    ../profiles/desktop.nix
    ../profiles/sysadmin.nix
  ];

  # Override specific user settings
  home = {
    username = "semyenov";
    homeDirectory = "/home/semyenov";
    stateVersion = "25.05";

    # User-specific packages
    packages = with pkgs; [
      cursor-appimage
      yandex-music
      nekoray
      thunderbird
    ];
  };

  # Override git configuration with user-specific details
  programs.git = {
    enable = true;
    userName = "Alexander Semyenov";
    userEmail = "semyenov@hotmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "nvim";
      pull.rebase = false;
      push.autoSetupRemote = true;
      diff.colorMoved = "default";
      merge.conflictstyle = "diff3";
    };
  };
}
