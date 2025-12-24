#!/bin/bash
set -euo pipefail

# Deployment script for backup system
# Run from repo root: ./deploy.sh

SEEDBOX_HOST="bhcopeland@192.168.0.242"
PROXMOX_HOST="root@192.168.0.240"

echo "=== Backup System Deployment ==="
echo

# Deploy to Desktop (local)
deploy_desktop() {
    echo "📍 Deploying to Desktop (local)..."

    # Copy script to system location
    sudo cp desktop/simple-btrfs-backup.sh /usr/local/bin/
    sudo chmod +x /usr/local/bin/simple-btrfs-backup.sh

    # Copy systemd units
    sudo cp desktop/btrfs-backup.service /etc/systemd/system/
    sudo cp desktop/btrfs-backup.timer /etc/systemd/system/

    # Reload systemd
    sudo systemctl daemon-reload

    # Enable timer if not already enabled
    if ! systemctl is-enabled btrfs-backup.timer &>/dev/null; then
        sudo systemctl enable btrfs-backup.timer
    fi

    echo "✓ Desktop deployed"
    echo "  - Script: /usr/local/bin/simple-btrfs-backup.sh"
    echo "  - Timer: btrfs-backup.timer ($(systemctl is-enabled btrfs-backup.timer))"
    echo
}

# Deploy to Seedbox
deploy_seedbox() {
    echo "📍 Deploying to Seedbox ($SEEDBOX_HOST)..."

    # Copy files to home directory first
    scp seedbox/rclone-chunked-backup.sh "$SEEDBOX_HOST:~/"
    scp seedbox/rclone-backup.service seedbox/rclone-backup.timer "$SEEDBOX_HOST:~/"

    # Move files and enable timer (using sudo -i)
    ssh -t "$SEEDBOX_HOST" 'sudo -i bash -c "
        mv /home/bhcopeland/rclone-chunked-backup.sh /root/
        chmod +x /root/rclone-chunked-backup.sh
        mv /home/bhcopeland/rclone-backup.service /etc/systemd/system/
        mv /home/bhcopeland/rclone-backup.timer /etc/systemd/system/
        systemctl daemon-reload
        systemctl is-enabled rclone-backup.timer || systemctl enable rclone-backup.timer
    "'

    echo "✓ Seedbox deployed"
    echo "  - Script: /root/rclone-chunked-backup.sh"
    echo "  - Timer: rclone-backup.timer"
    echo
}

# Deploy to Proxmox
deploy_proxmox() {
    echo "📍 Deploying to Proxmox ($PROXMOX_HOST)..."

    # Copy ZFS backup script
    scp proxmox/zfs-only-backup.sh "$PROXMOX_HOST:/root/"
    ssh "$PROXMOX_HOST" "chmod +x /root/zfs-only-backup.sh"

    # Copy systemd units
    scp proxmox/zfs-backup.service proxmox/zfs-backup.timer "$PROXMOX_HOST:/tmp/"
    ssh "$PROXMOX_HOST" "mv /tmp/zfs-backup.* /etc/systemd/system/ && systemctl daemon-reload"

    # Enable timer if not already enabled
    ssh "$PROXMOX_HOST" "systemctl is-enabled zfs-backup.timer || systemctl enable zfs-backup.timer"

    echo "✓ Proxmox deployed"
    echo "  - Script: /root/zfs-only-backup.sh"
    echo "  - Timer: zfs-backup.timer"
    echo
}

# Main deployment
main() {
    # Check if we're in the right directory
    if [[ ! -f "deploy.sh" ]]; then
        echo "Error: Run this script from the repo root"
        exit 1
    fi

    # Parse arguments
    if [[ $# -eq 0 ]]; then
        # Deploy all
        deploy_desktop
        deploy_seedbox
        deploy_proxmox
    else
        # Deploy specific targets
        for target in "$@"; do
            case "$target" in
                desktop)
                    deploy_desktop
                    ;;
                seedbox)
                    deploy_seedbox
                    ;;
                proxmox)
                    deploy_proxmox
                    ;;
                *)
                    echo "Unknown target: $target"
                    echo "Valid targets: desktop, seedbox, proxmox"
                    exit 1
                    ;;
            esac
        done
    fi

    echo "=== Deployment Complete ==="
    echo
    echo "Next steps:"
    echo "  Desktop:  systemctl status btrfs-backup.timer"
    echo "  Seedbox:  ssh $SEEDBOX_HOST 'sudo systemctl status rclone-backup.timer'"
    echo "  Proxmox:  ssh $PROXMOX_HOST 'systemctl status zfs-backup.timer'"
}

main "$@"
