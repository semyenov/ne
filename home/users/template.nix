{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ../minimal.nix  # Base configuration for all users
    # Add additional profiles as needed:
    # ../profiles/common.nix
    # ../profiles/desktop.nix
    # ../profiles/sysadmin.nix
  ];

  # User-specific settings
  home = {
    username = "USERNAME";  # Replace with actual username
    homeDirectory = "/home/USERNAME";  # Replace with actual username
    stateVersion = "25.05";

    # User-specific packages
    packages = with pkgs; [
      # Add user-specific packages here
    ];
  };

  # Override git configuration with user-specific details
  programs.git = {
    userName = "Full Name";  # Replace with user's full name
    userEmail = "email@example.com";  # Replace with user's email
  };

  # Add any other user-specific configurations here
}