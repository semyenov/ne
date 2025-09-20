{ pkgs, lib }:

# Official Cursor AppImage with fixes for native modules
pkgs.appimageTools.wrapType2 {
  name = "cursor";
  pname = "cursor";
  version = "1.6.35";
  src = pkgs.fetchurl {
    url = "https://downloads.cursor.com/production/b753cece5c67c47cb5637199a5a5de2b7100c18f/linux/x64/Cursor-1.6.35-x86_64.AppImage";
    sha256 = "1qpkvs6zga979hhki49blyckffjp9pk49vhfn9nv57bxgjrbqszb";
  };

  # Fix for native modules
  extraInstallCommands = ''
    # Install desktop entry
    install -m 444 -D ${pkgs.appimageTools.extract {
      pname = "cursor";
      version = "1.6.35";
      src = pkgs.fetchurl {
        url = "https://downloads.cursor.com/production/b753cece5c67c47cb5637199a5a5de2b7100c18f/linux/x64/Cursor-1.6.35-x86_64.AppImage";
        sha256 = "1qpkvs6zga979hhki49blyckffjp9pk49vhfn9nv57bxgjrbqszb";
      };
    }}/cursor.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/cursor.desktop \
      --replace 'Exec=AppRun' 'Exec=cursor'

    # Create symlink for the binary
    mkdir -p $out/bin
    ln -s $out/bin/cursor $out/bin/Cursor || true
  '';

  extraPkgs = pkgs: with pkgs; [
    # X11 libraries
    xorg.libX11
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXinerama
    xorg.libXi
    xorg.libXfixes
    xorg.libXrender
    xorg.libXext
    xorg.libXtst
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libxcb
    xorg.libXScrnSaver
    libxkbcommon

    # Graphics
    libGL
    libGLU
    mesa
    vulkan-loader
    libdrm

    # GTK/System
    glib
    gtk3
    cairo
    pango
    atk
    gdk-pixbuf
    at-spi2-atk
    at-spi2-core

    # Audio
    alsa-lib
    pulseaudio

    # System libraries
    fontconfig
    freetype
    dbus
    nss
    nspr
    cups
    expat
    libnotify
    libuuid
    libsecret
    systemd

    # Additional libraries for native modules
    stdenv.cc.cc.lib
    xorg.libxkbfile
    libkrb5
    keyutils
    e2fsprogs
    util-linux
  ];
}
