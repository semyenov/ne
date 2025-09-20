{ config, pkgs, lib, ... }:

{
  # Base home-manager configuration for all users
  # This provides the minimal setup that every user should have
  
  home.stateVersion = "25.05";
  
  # Basic shell configuration
  programs = {
    bash = {
      enable = true;
      shellAliases = {
        ll = "ls -la";
        gs = "git status";
        gc = "git commit";
        gp = "git push";
      };
    };
    
    git = {
      enable = lib.mkDefault true;
      # User details can be overridden in user-specific configs
      extraConfig = {
        init.defaultBranch = lib.mkDefault "main";
        pull.rebase = lib.mkDefault false;
        core.editor = lib.mkDefault "vim";
      };
    };
    
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
  };
  
  # XDG directories
  xdg.enable = true;
  
  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}