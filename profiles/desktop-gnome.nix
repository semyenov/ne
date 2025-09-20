{ config, lib, pkgs, ... }:

{
  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # X11/Wayland + GNOME
  services.xserver = {
    enable = true;
    videoDrivers = [ "nvidia" ];
    displayManager.gdm = {
      enable = true;
      wayland = true;
    };
    desktopManager.gnome.enable = true;
    xkb = {
      layout = "us";
      variant = "";
      options = "caps:escape";
    };
  };

  services.printing.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Fonts
  fonts = {
    packages = with pkgs; [
      nerd-fonts.recursive-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
    ];

    fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [ "Noto Serif" "Liberation Serif" ];
        sansSerif = [ "Noto Sans" "Liberation Sans" ];
        monospace = [ "RecMonoLinear Nerd Font" "Noto Sans Mono" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
  };

  # Desktop helpful packages
  environment.systemPackages = with pkgs; [
    alacritty
    kitty
    ghostty
    gnome-themes-extra  # Fix missing GTK4 theme files
    gnome-tweaks
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
  ];

  # Fix gnome-keyring PAM configuration
  security.pam.services = {
    gdm.enableGnomeKeyring = true;
    gdm-password.enableGnomeKeyring = true;
  };

  # GNOME specific services
  services.gnome = {
    gnome-keyring.enable = true;
    gnome-settings-daemon.enable = true;
  };

  # Disable USBGuard if not needed (causing errors)
  services.usbguard.enable = lib.mkForce false;
}
