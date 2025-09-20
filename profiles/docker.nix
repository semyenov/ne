{ config, lib, pkgs, ... }:

{
  # Docker configuration
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
  };

  # Enable NVIDIA in containers via toolkit when present
  hardware.nvidia-container-toolkit.enable = lib.mkDefault true;
  
  # Note: Users should be added to docker group in their host configuration
  # Example in configuration.nix:
  # users.users.youruser.extraGroups = [ "docker" ];
}


