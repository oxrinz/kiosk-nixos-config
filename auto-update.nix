{ config, lib, pkgs, ... }:
{
  options.services.nixosAutoUpdate = {
    enable = lib.mkEnableOption "NixOS auto-update service";
    repoUrl = lib.mkOption {
      type = lib.types.str;
      description = "URL of the Git repository containing NixOS configuration";
    };
    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Git branch to track";
    };
  };

  config = lib.mkIf config.services.nixosAutoUpdate.enable {
    environment.systemPackages = [ pkgs.git ];
    
    environment.etc."nixos/update-config.sh" = {
      mode = "0755";  # Make sure it's executable
      source = ./update-config.sh;  # Reference your external script
    };

    systemd.services.nixos-config-update = {
      description = "NixOS Configuration Update Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do /etc/nixos/update-config.sh; sleep 3d; done'";
        Restart = "always";
        RestartSec = "5s";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}