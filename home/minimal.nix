{ config, pkgs, lib, ... }:

{
  # Minimal home-manager configuration for enterprise users
  # Most configuration is handled by the enterprise module
  
  home.stateVersion = "24.11";
  
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
      enable = true;
      # User details are set by enterprise module based on username
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = false;
        core.editor = "vim";
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