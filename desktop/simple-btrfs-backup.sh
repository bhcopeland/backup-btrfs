#!/bin/bash
set -euo pipefail

# Simple btrfs to ZFS backup script
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SSH_HOST="192.168.0.241"
SSH_USER="bhcopeland"
REMOTE_DIR="/mnt/backup/pickles"

# Function to backup a subvolume
backup_subvolume() {
    local subvol="$1"
    local name=$(basename "$subvol")

    echo "=== Backing up $subvol ==="

    # Create snapshot
    local snapshot="/snapshots/${name}_${TIMESTAMP}"
    echo "Creating snapshot: $snapshot"
    sudo btrfs subvolume snapshot -r "$subvol" "$snapshot"

    # Create remote directory
    ssh "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_DIR/$name"

    # Check for previous backup for incremental
    local prev_backup=$(ssh "$SSH_USER@$SSH_HOST" "ls -1 $REMOTE_DIR/$name/*.btrfs.zst 2>/dev/null | tail -1" || echo "")
    local prev_snapshot=""

    if [[ -n "$prev_backup" ]]; then
        # Find matching local snapshot
        local prev_timestamp=$(basename "$prev_backup" | sed 's/.*_\([0-9_]*\)\.btrfs\.zst/\1/')
        prev_snapshot="/snapshots/${name}_${prev_timestamp}"

        if [[ -d "$prev_snapshot" ]]; then
            echo "Found previous snapshot: $prev_snapshot"
            echo "Sending incremental backup (compressed)..."
            sudo btrfs send -p "$prev_snapshot" "$snapshot" | \
                zstd -T0 -3 | \
                ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/$name/incremental_${TIMESTAMP}.btrfs.zst"
        else
            echo "Previous snapshot not found locally, sending full backup (compressed)..."
            sudo btrfs send "$snapshot" | \
                zstd -T0 -3 | \
                ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/$name/full_${TIMESTAMP}.btrfs.zst"
        fi
    else
        echo "No previous backup found, sending full backup (compressed)..."
        sudo btrfs send "$snapshot" | \
            zstd -T0 -3 | \
            ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/$name/full_${TIMESTAMP}.btrfs.zst"
    fi

    echo "Backup completed for $subvol"

    # Smart cleanup: keep last 8 + first of each month for 3 months
    ssh "$SSH_USER@$SSH_HOST" "
        cd $REMOTE_DIR/$name

        # Get current date and 3 months ago
        current_month=\$(date +%Y%m)
        month_1=\$(date -d '1 month ago' +%Y%m)
        month_2=\$(date -d '2 months ago' +%Y%m)
        month_3=\$(date -d '3 months ago' +%Y%m)

        # Mark files to keep (latest 8)
        ls -t *.btrfs.zst *.btrfs 2>/dev/null | head -8 > /tmp/keep_files.txt

        # Mark first backup of each month for last 3 months
        for month in \$current_month \$month_1 \$month_2 \$month_3; do
            ls -1 *_\${month}*.btrfs.zst *_\${month}*.btrfs 2>/dev/null | head -1 >> /tmp/keep_files.txt || true
        done

        # Sort and dedupe the keep list
        sort -u /tmp/keep_files.txt > /tmp/keep_files_uniq.txt

        # Delete files not in keep list
        for file in *.btrfs.zst *.btrfs 2>/dev/null; do
            if ! grep -qx \"\$file\" /tmp/keep_files_uniq.txt; then
                echo \"Removing old backup: \$file\"
                rm -f \"\$file\"
            fi
        done

        rm -f /tmp/keep_files*.txt
        echo \"Cleaned old backups, keeping latest 8 + monthly for 3 months\"
    " || true

    # Keep only last 8 local snapshots
    local old_snapshots=($(ls -1 /snapshots/${name}_* 2>/dev/null | head -n -8 || true))
    for old in "${old_snapshots[@]}"; do
        if [[ -d "$old" ]]; then
            echo "Removing old snapshot: $old"
            sudo btrfs subvolume delete "$old"
        fi
    done
}

# Create snapshots directory
sudo mkdir -p /snapshots

# Backup home subvolume
backup_subvolume "/home"

echo "=== Backup completed successfully ==="
