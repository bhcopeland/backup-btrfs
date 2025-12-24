#!/bin/bash
set -euo pipefail

# Unified backup script for both Btrfs and ZFS
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SSH_HOST="192.168.0.241"
SSH_USER="bhcopeland"
REMOTE_DIR="/mnt/backup/pickles"

echo "=== Starting Unified Backup at $(date) ==="

# Function to backup Btrfs subvolume
backup_btrfs_subvolume() {
    local subvol="$1"
    local name=$(basename "$subvol")
    
    echo "=== Backing up Btrfs subvolume $subvol ==="
    
    # Create snapshot
    local snapshot="/snapshots/${name}_${TIMESTAMP}"
    echo "Creating Btrfs snapshot: $snapshot"
    sudo btrfs subvolume snapshot -r "$subvol" "$snapshot"
    
    # Create remote directory
    ssh "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_DIR/btrfs_$name"
    
    # Check for previous backup for incremental
    local prev_backup=$(ssh "$SSH_USER@$SSH_HOST" "ls -1 $REMOTE_DIR/btrfs_$name/*.btrfs 2>/dev/null | tail -1" || echo "")
    local prev_snapshot=""
    
    if [[ -n "$prev_backup" ]]; then
        # Find matching local snapshot
        local prev_timestamp=$(basename "$prev_backup" | sed 's/.*_\([0-9_]*\)\.btrfs/\1/')
        prev_snapshot="/snapshots/${name}_${prev_timestamp}"
        
        if [[ -d "$prev_snapshot" ]]; then
            echo "Sending incremental Btrfs backup..."
            sudo btrfs send -p "$prev_snapshot" "$snapshot" | \
                ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/btrfs_$name/incremental_${TIMESTAMP}.btrfs"
        else
            echo "Sending full Btrfs backup..."
            sudo btrfs send "$snapshot" | \
                ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/btrfs_$name/full_${TIMESTAMP}.btrfs"
        fi
    else
        echo "Sending full Btrfs backup..."
        sudo btrfs send "$snapshot" | \
            ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/btrfs_$name/full_${TIMESTAMP}.btrfs"
    fi
    
    # Cleanup old local snapshots (keep 5)
    local old_snapshots=($(ls -1 /snapshots/${name}_* 2>/dev/null | head -n -5 || true))
    for old in "${old_snapshots[@]}"; do
        if [[ -d "$old" ]]; then
            echo "Removing old Btrfs snapshot: $old"
            sudo btrfs subvolume delete "$old"
        fi
    done
    
    # Cleanup old remote backups (keep 10)
    ssh "$SSH_USER@$SSH_HOST" "
        cd $REMOTE_DIR/btrfs_$name
        ls -t *.btrfs 2>/dev/null | tail -n +11 | xargs -r rm -f
    " || true
}

# Function to backup ZFS dataset
backup_zfs_dataset() {
    local dataset="$1"
    local dataset_name=$(basename "$dataset")
    
    echo "=== Backing up ZFS dataset $dataset ==="
    
    # Create snapshot
    local snapshot="${dataset}@backup_${TIMESTAMP}"
    echo "Creating ZFS snapshot: $snapshot"
    sudo zfs snapshot "$snapshot"
    
    # Create remote directory
    ssh "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_DIR/zfs_$dataset_name"
    
    # Get snapshots for incremental backup
    local snapshots=($(sudo zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local num_snapshots=${#snapshots[@]}
    
    if [[ $num_snapshots -gt 1 ]]; then
        local prev_snapshot="${snapshots[-2]}"
        echo "Sending incremental ZFS backup..."
        sudo zfs send -i "$prev_snapshot" "$snapshot" | \
            ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/zfs_$dataset_name/incremental_${TIMESTAMP}.zfs"
    else
        echo "Sending full ZFS backup..."
        sudo zfs send "$snapshot" | \
            ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/zfs_$dataset_name/full_${TIMESTAMP}.zfs"
    fi
    
    # Cleanup old local snapshots (keep 5)
    local all_snapshots=($(sudo zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local total_snapshots=${#all_snapshots[@]}
    
    if [[ $total_snapshots -gt 5 ]]; then
        local to_delete=$((total_snapshots - 5))
        for ((i=0; i<to_delete; i++)); do
            echo "Deleting old ZFS snapshot: ${all_snapshots[i]}"
            sudo zfs destroy "${all_snapshots[i]}"
        done
    fi
    
    # Cleanup old remote backups (keep 10)
    ssh "$SSH_USER@$SSH_HOST" "
        cd $REMOTE_DIR/zfs_$dataset_name
        ls -t *.zfs 2>/dev/null | tail -n +11 | xargs -r rm -f
    " || true
}

# Create directories
sudo mkdir -p /snapshots
ssh "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_DIR"

echo "Starting Btrfs backups..."
# Backup Btrfs subvolumes
backup_btrfs_subvolume "/home"
# Add more Btrfs subvolumes as needed:
# backup_btrfs_subvolume "/root"

echo "Starting ZFS backups..."
# Backup ZFS datasets
backup_zfs_dataset "rpool/opt_data"

echo "=== Unified backup completed successfully at $(date) ==="