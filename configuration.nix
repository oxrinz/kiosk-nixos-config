{ config, lib, pkgs, ... }: {
  imports = [ ./auto-update.nix ./hardware-configuration.nix ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/mmcblk1";
  };

  services.openssh = {
    enable = true;
    permitRootLogin = "yes";
    settings = { PasswordAuthentication = false; };
  };

  users.users.kiosk = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "megasush";
  };

  services.xserver.serverLayoutSection = ''
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
    Option "BlankTime" "0"
  '';

  services.xserver = {
    enable = true;
    displayManager = {
      autoLogin = {
        enable = true;
        user = "kiosk";
      };
      defaultSession = "none+openbox";
    };
    windowManager.openbox.enable = true;
  };

  services.nixosAutoUpdate = {
    enable = true;
    repoUrl = "https://github.com/oxrinz/kiosk-nixos-config.git";
  };

  systemd.services.kiosk-display = {
    description = "Kiosk Display";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = { DISPLAY = ":0"; };
    serviceConfig = {
      Type = "simple";
      User = "kiosk";
      Restart = "always";
      ExecStart =
        "${pkgs.chromium}/bin/chromium --incognito --noerrdialogs https://oxrinz.com/sumika";
      RestartSec = "15";
    };
  };

  systemd.services.unclutter = {
    description = "Hide cursor";
    after = [ "xserver.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = { DISPLAY = ":0"; };
    serviceConfig = {
      Type = "simple";
      User = "kiosk";
      ExecStart = "${pkgs.unclutter}/bin/unclutter";
      Restart = "always";
    };
  };

  networking = {
    wireless = {
      enable = true;
      networks = {
        "Zyxel_B981" = {
          psk = "X4MXD4XXJA";
          priority = 10;
        };
      };
    };

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    chromium
    openbox
    networkmanager
    xterm
    unclutter
    git
    bash
  ];

  system.stateVersion = "24.05";
}
