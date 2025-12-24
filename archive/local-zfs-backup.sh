#!/bin/bash
set -euo pipefail

# Local ZFS backup script (runs on ZFS server)
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_DIR="/mnt/backup/pickles"
ZFS_DATASET="rpool/opt_data"

# Function to backup a ZFS dataset locally
backup_zfs_dataset() {
    local dataset="$1"
    local dataset_name=$(basename "$dataset")
    local backup_subdir="$BACKUP_DIR/zfs_$dataset_name"
    
    echo "=== Backing up ZFS dataset $dataset ==="
    
    # Create backup directory
    mkdir -p "$backup_subdir"
    
    # Create snapshot
    local snapshot="${dataset}@backup_${TIMESTAMP}"
    echo "Creating ZFS snapshot: $snapshot"
    zfs snapshot "$snapshot"
    
    # Get list of existing snapshots (for incremental)
    local snapshots=($(zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local num_snapshots=${#snapshots[@]}
    
    if [[ $num_snapshots -gt 1 ]]; then
        # Incremental backup from previous snapshot
        local prev_snapshot="${snapshots[-2]}"  # Second to last snapshot
        echo "Sending incremental backup from $prev_snapshot to $snapshot"
        
        zfs send -i "$prev_snapshot" "$snapshot" > "$backup_subdir/incremental_${TIMESTAMP}.zfs"
    else
        # Full backup (first snapshot)
        echo "Sending full backup of $snapshot"
        
        zfs send "$snapshot" > "$backup_subdir/full_${TIMESTAMP}.zfs"
    fi
    
    echo "Backup completed for $dataset"
    echo "Backup size: $(du -h "$backup_subdir"/*_${TIMESTAMP}.zfs | cut -f1)"
    
    # Keep only last 10 backup files
    cd "$backup_subdir"
    ls -t *.zfs 2>/dev/null | tail -n +11 | xargs -r rm -f
    echo "Cleaned old remote ZFS backups, keeping latest 10"
    
    # Keep only last 5 local snapshots
    local all_snapshots=($(zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local total_snapshots=${#all_snapshots[@]}
    
    if [[ $total_snapshots -gt 5 ]]; then
        local to_delete=$((total_snapshots - 5))
        for ((i=0; i<to_delete; i++)); do
            echo "Deleting old snapshot: ${all_snapshots[i]}"
            zfs destroy "${all_snapshots[i]}"
        done
    fi
}

# Create backup directory structure
mkdir -p "$BACKUP_DIR"

# Backup the ZFS dataset
backup_zfs_dataset "$ZFS_DATASET"

echo "=== Local ZFS backup completed successfully ==="