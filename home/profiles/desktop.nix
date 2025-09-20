{ config, pkgs, lib, inputs, ... }:

{
  # Desktop applications and XDG/GTK settings for the user
  home.packages = with pkgs; [
    brave
    chromium
    vlc
    spotify
    obs-studio
    obsidian
    libreoffice
    thunderbird
    dconf
    gnome-tweaks
    cursor-appimage
    nekoray
    yandex-music
    telegram-desktop
    bun
    nodejs
  ];

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      desktop = "$HOME/Desktop";
      documents = "$HOME/Documents";
      download = "$HOME/Downloads";
      music = "$HOME/Music";
      pictures = "$HOME/Pictures";
      videos = "$HOME/Videos";
    };
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "brave-browser.desktop";
        "x-scheme-handler/http" = "brave-browser.desktop";
        "x-scheme-handler/https" = "brave-browser.desktop";
        "application/pdf" = "org.gnome.Evince.desktop";
        "image/png" = "org.gnome.eog.desktop";
        "image/jpeg" = "org.gnome.eog.desktop";
      };
    };
  };

  gtk = {
    enable = true;
    theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
    iconTheme = { name = "Papirus-Dark"; package = pkgs.papirus-icon-theme; };
    font = { name = "Ubuntu"; size = 11; };
  };

  qt = { enable = true; platformTheme.name = "gtk"; style.name = "adwaita-dark"; };

  programs.vscode.enable = true;
}
