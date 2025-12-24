#!/bin/bash
set -euo pipefail

# Local unified backup script (runs on ZFS server, receives Btrfs over SSH)
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_DIR="/mnt/backup/pickles"
BTRFS_HOST="192.168.0.191"  # Your Btrfs system (pickles)
BTRFS_USER="ben"

echo "=== Starting Local Unified Backup at $(date) ==="

# Function to receive Btrfs backup via SSH
backup_remote_btrfs() {
    local subvol="$1"
    local name=$(basename "$subvol")
    local backup_subdir="$BACKUP_DIR/btrfs_$name"
    
    echo "=== Backing up remote Btrfs subvolume $subvol ==="
    
    # Create backup directory
    mkdir -p "$backup_subdir"
    
    # Run the Btrfs backup command on remote host and receive the stream
    echo "Requesting Btrfs backup from $BTRFS_HOST..."
    
    # Check if there's a previous backup for incremental
    local prev_backup=$(ls -1 "$backup_subdir"/*.btrfs 2>/dev/null | tail -1 || echo "")
    
    if [[ -n "$prev_backup" ]]; then
        echo "Found previous backup, requesting incremental..."
        # You'll need to implement the remote incremental logic
        ssh "$BTRFS_USER@$BTRFS_HOST" "sudo /home/ben/GitHub/backup-btrfs/remote-btrfs-send.sh $subvol incremental" > "$backup_subdir/incremental_${TIMESTAMP}.btrfs"
    else
        echo "No previous backup, requesting full backup..."
        ssh "$BTRFS_USER@$BTRFS_HOST" "sudo /home/ben/GitHub/backup-btrfs/remote-btrfs-send.sh $subvol full" > "$backup_subdir/full_${TIMESTAMP}.btrfs"
    fi
    
    echo "Backup size: $(du -h "$backup_subdir"/*_${TIMESTAMP}.btrfs | cut -f1)"
    
    # Cleanup old backups (keep 10)
    cd "$backup_subdir"
    ls -t *.btrfs 2>/dev/null | tail -n +11 | xargs -r rm -f
}

# Function to backup local ZFS dataset
backup_local_zfs() {
    local dataset="$1"
    local dataset_name=$(basename "$dataset")
    local backup_subdir="$BACKUP_DIR/zfs_$dataset_name"
    
    echo "=== Backing up local ZFS dataset $dataset ==="
    
    # Create backup directory
    mkdir -p "$backup_subdir"
    
    # Create snapshot
    local snapshot="${dataset}@backup_${TIMESTAMP}"
    echo "Creating ZFS snapshot: $snapshot"
    zfs snapshot "$snapshot"
    
    # Get snapshots for incremental backup
    local snapshots=($(zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local num_snapshots=${#snapshots[@]}
    
    if [[ $num_snapshots -gt 1 ]]; then
        local prev_snapshot="${snapshots[-2]}"
        echo "Sending incremental ZFS backup..."
        zfs send -i "$prev_snapshot" "$snapshot" > "$backup_subdir/incremental_${TIMESTAMP}.zfs"
    else
        echo "Sending full ZFS backup..."
        zfs send "$snapshot" > "$backup_subdir/full_${TIMESTAMP}.zfs"
    fi
    
    echo "Backup size: $(du -h "$backup_subdir"/*_${TIMESTAMP}.zfs | cut -f1)"
    
    # Cleanup old local snapshots (keep 5)
    local all_snapshots=($(zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local total_snapshots=${#all_snapshots[@]}
    
    if [[ $total_snapshots -gt 5 ]]; then
        local to_delete=$((total_snapshots - 5))
        for ((i=0; i<to_delete; i++)); do
            echo "Deleting old ZFS snapshot: ${all_snapshots[i]}"
            zfs destroy "${all_snapshots[i]}"
        done
    fi
    
    # Cleanup old backup files (keep 10)
    cd "$backup_subdir"
    ls -t *.zfs 2>/dev/null | tail -n +11 | xargs -r rm -f
}

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "Starting remote Btrfs backups..."
# Backup remote Btrfs subvolumes
backup_remote_btrfs "/home"

echo "Starting local ZFS backups..."
# Backup local ZFS datasets  
backup_local_zfs "rpool/opt_data"

echo "=== Local unified backup completed successfully at $(date) ==="