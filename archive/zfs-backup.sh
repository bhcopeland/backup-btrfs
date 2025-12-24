#!/bin/bash
set -euo pipefail

# ZFS dataset backup script using zfs send
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SSH_HOST="192.168.0.241"
SSH_USER="bhcopeland"
REMOTE_DIR="/mnt/backup/pickles"
ZFS_DATASET="rpool/opt_data"

# Function to backup a ZFS dataset
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
    
    # Get list of existing snapshots (for incremental)
    local snapshots=($(sudo zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local num_snapshots=${#snapshots[@]}
    
    if [[ $num_snapshots -gt 1 ]]; then
        # Incremental backup from previous snapshot
        local prev_snapshot="${snapshots[-2]}"  # Second to last snapshot
        echo "Sending incremental backup from $prev_snapshot to $snapshot"
        
        sudo zfs send -i "$prev_snapshot" "$snapshot" | \
            ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/zfs_$dataset_name/incremental_${TIMESTAMP}.zfs"
    else
        # Full backup (first snapshot)
        echo "Sending full backup of $snapshot"
        
        sudo zfs send "$snapshot" | \
            ssh "$SSH_USER@$SSH_HOST" "cat > $REMOTE_DIR/zfs_$dataset_name/full_${TIMESTAMP}.zfs"
    fi
    
    echo "Backup completed for $dataset"
    
    # Keep only last 10 remote backup files
    ssh "$SSH_USER@$SSH_HOST" "
        cd $REMOTE_DIR/zfs_$dataset_name
        ls -t *.zfs 2>/dev/null | tail -n +11 | xargs -r rm -f
        echo 'Cleaned old remote ZFS backups, keeping latest 10'
    " || true
    
    # Keep only last 5 local snapshots
    local all_snapshots=($(sudo zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local total_snapshots=${#all_snapshots[@]}
    
    if [[ $total_snapshots -gt 5 ]]; then
        local to_delete=$((total_snapshots - 5))
        for ((i=0; i<to_delete; i++)); do
            echo "Deleting old snapshot: ${all_snapshots[i]}"
            sudo zfs destroy "${all_snapshots[i]}"
        done
    fi
}

# Create remote backup directory structure
ssh "$SSH_USER@$SSH_HOST" "mkdir -p $REMOTE_DIR"

# Backup the ZFS dataset
backup_zfs_dataset "$ZFS_DATASET"

echo "=== ZFS backup completed successfully ==="