{ config, lib, pkgs, ... }: {
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
      mode = "0755";
      text = ''
        #!/bin/bash
        REPO_URL="${config.services.nixosAutoUpdate.repoUrl}"
        REPO_BRANCH="${config.services.nixosAutoUpdate.branch}"
        CONFIG_DIR="/etc/nixos"
        BACKUP_DIR="/etc/nixos/backups"
        LOG_FILE="/var/log/nixos-updates.log"

        log_message() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
          echo "$1"
        }

        sudo mkdir -p $BACKUP_DIR

        if ! sudo git ls-remote $REPO_URL &>/dev/null; then
          log_message "Cannot reach git remote, skipping update"
          exit 1
        fi

        cd $CONFIG_DIR

        sudo git fetch origin $REPO_BRANCH

        LOCAL_HASH=$(git -C $CONFIG_DIR rev-parse HEAD)
        REMOTE_HASH=$(git -C $CONFIG_DIR rev-parse origin/$REPO_BRANCH)

        if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
          exit 0
        fi

        backup_timestamp=$(date +%Y%m%d_%H%M%S)
        cp $CONFIG_DIR/configuration.nix $BACKUP_DIR/configuration.nix.$backup_timestamp

        if sudo git -C $CONFIG_DIR pull origin $REPO_BRANCH; then
          log_message "Pulled new configuration"
          if sudo -E nixos-rebuild test; then
            log_message "Configuration test successful, applying changes"
            if sudo -E nixos-rebuild switch; then
              log_message "Successfully updated NixOS configuration"
            else
              log_message "Failed to switch to new configuration"
              cp $BACKUP_DIR/configuration.nix.$backup_timestamp $CONFIG_DIR/configuration.nix
              sudo -E nixos-rebuild switch
            fi
          else
            log_message "Configuration test failed, keeping current configuration"
            sudo git -C $CONFIG_DIR reset --hard $LOCAL_HASH
          fi
        else
          log_message "Failed to pull updates"
        fi
      '';
    };

    systemd.services.nixos-config-update = {
      description = "NixOS Configuration Update Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/etc/nixos";
        Environment = [
          "PATH=${pkgs.git}/bin:${pkgs.bash}/bin:/run/current-system/sw/bin"
          "HOME=/root"
          "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix"
        ];
        ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/update-config.sh";
        Restart = "always";
        RestartSec = "15s";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}