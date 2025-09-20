{ config, lib, pkgs, ... }:

{
  # Security hardening configuration
  
  # Common secure defaults
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
  };

  # Enable firewall
  networking.firewall = {
    enable = true;
    allowPing = false;
    logReversePathDrops = true;
  };

  # Security kernel parameters
  boot.kernel.sysctl = {
    # Network hardening
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    
    # Kernel hardening
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
  };

  # USB device policy - disabled by default as it can cause issues
  # Enable per-host if needed with proper rules
  services.usbguard.enable = lib.mkDefault false;

  # Auditing
  security.auditd.enable = lib.mkDefault true;
  
  # Additional security settings
  security.sudo = {
    execWheelOnly = true;
    extraConfig = ''
      Defaults requiretty
      Defaults use_pty
      Defaults umask_override
      Defaults umask=0022
    '';
  };
}


