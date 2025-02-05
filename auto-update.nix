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
      mode = "0755";
      text = ''
        #!/bin/bash
        REPO_URL="${config.services.nixosAutoUpdate.repoUrl}"
        REPO_BRANCH="${config.services.nixosAutoUpdate.branch}"
        CONFIG_DIR="/etc/nixos"
        BACKUP_DIR="/etc/nixos/backups"
        LOG_FILE="/var/log/nixos-updates.log"
        LAST_HASH_FILE="/var/run/nixos-last-hash"

        # Just fetch the latest ref without cloning
        REMOTE_HASH=$(git ls-remote $REPO_URL $REPO_BRANCH | cut -f1)
        if [ -z "$REMOTE_HASH" ]; then
          exit 1
        fi

        # Check if hash changed
        if [ -f "$LAST_HASH_FILE" ]; then
          LAST_HASH=$(cat "$LAST_HASH_FILE")
          if [ "$REMOTE_HASH" = "$LAST_HASH" ]; then
            exit 0
          fi
        fi

        # Save new hash
        echo "$REMOTE_HASH" > "$LAST_HASH_FILE"

        # Trigger the actual update
        /etc/nixos/update-config.sh
      '';
    };

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

        # Check for lock file
        LOCK_FILE="/var/run/nixos-update.lock"
        if [ -e "$LOCK_FILE" ]; then
          pid=$(cat "$LOCK_FILE")
          if kill -0 "$pid" 2>/dev/null; then
            exit 0  # Silently exit if another update is running
          fi
        fi
        echo $$ > "$LOCK_FILE"
        trap 'rm -f "$LOCK_FILE"' EXIT

        mkdir -p $BACKUP_DIR
        backup_timestamp=$(date +%Y%m%d_%H%M%S)
        cp $CONFIG_DIR/configuration.nix $BACKUP_DIR/configuration.nix.$backup_timestamp

        if git -C $CONFIG_DIR pull origin $REPO_BRANCH; then
          log_message "Pulled new configuration"
          if nixos-rebuild test; then
            log_message "Configuration test successful, applying changes"
            if nixos-rebuild switch; then
              log_message "Successfully updated NixOS configuration"
            else
              log_message "Failed to switch to new configuration"
              cp $BACKUP_DIR/configuration.nix.$backup_timestamp $CONFIG_DIR/configuration.nix
              nixos-rebuild switch
            fi
          else
            log_message "Configuration test failed, keeping current configuration"
            git -C $CONFIG_DIR reset --hard HEAD@{1}
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
        ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do /etc/nixos/update-config.sh; sleep 5; done'";
        Restart = "always";
        RestartSec = "5s";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}