#!/bin/bash
set -euo pipefail

# Pure ZFS backup script for Proxmox server
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_BASE="/dpool/backup/zfs-snapshots"
LOG_FILE="/var/log/zfs-backup.log"

# ZFS datasets to backup
ZFS_DATASETS=(
    "dpool/Photos"
    "rpool/opt_data"
    "rpool/data/subvol-100-disk-0"
    "rpool/data/subvol-101-disk-0"
    "rpool/data/subvol-102-disk-0"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

backup_zfs_dataset() {
    local dataset="$1"
    local dataset_safe=$(echo "$dataset" | tr '/' '_')
    local backup_dir="$BACKUP_BASE/$dataset_safe"
    
    log "=== Backing up ZFS dataset: $dataset ==="
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create new snapshot
    local snapshot="${dataset}@backup_${TIMESTAMP}"
    log "Creating snapshot: $snapshot"
    zfs snapshot "$snapshot"
    
    # Get previous snapshots for incremental backup
    local snapshots=($(zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local num_snapshots=${#snapshots[@]}
    
    if [[ $num_snapshots -gt 1 ]]; then
        # Incremental backup (compressed)
        local prev_snapshot="${snapshots[-2]}"
        local backup_file="$backup_dir/incremental_${TIMESTAMP}.zfs.zst"

        log "Creating compressed incremental backup from $prev_snapshot"
        zfs send -i "$prev_snapshot" "$snapshot" | zstd -T0 -3 > "$backup_file"

        local size=$(du -h "$backup_file" | cut -f1)
        log "Incremental backup completed: $size"
    else
        # Full backup (compressed)
        local backup_file="$backup_dir/full_${TIMESTAMP}.zfs.zst"

        log "Creating compressed full backup"
        zfs send "$snapshot" | zstd -T0 -3 > "$backup_file"

        local size=$(du -h "$backup_file" | cut -f1)
        log "Full backup completed: $size"
    fi
    
    # Cleanup old backup files
    cd "$backup_dir"
    # Cleanup old incremental backup files (keep last 10)
    log "Cleaning up old incremental backup files..."
    ls -t incremental_*.zfs.zst 2>/dev/null | tail -n +11 | while read old_file; do
        log "Removing old incremental backup: $old_file"
        rm -f "$old_file"
    done

    # Cleanup old full backup files (keep last 2)
    log "Cleaning up old full backup files..."
    ls -t full_*.zfs.zst 2>/dev/null | tail -n +3 | while read old_file; do
        log "Removing old full backup: $old_file"
        rm -f "$old_file"
    done

    # Cleanup old snapshots (keep last 5)
    log "Cleaning up old snapshots..."
    local all_snapshots=($(zfs list -t snapshot -o name -H "$dataset" | grep "@backup_" | sort))
    local total=${#all_snapshots[@]}

    if [[ $total -gt 5 ]]; then
        local to_delete=$((total - 5))
        for ((i=0; i<to_delete; i++)); do
            log "Destroying old snapshot: ${all_snapshots[i]}"
            zfs destroy "${all_snapshots[i]}"
        done
    fi

    log "Backup completed for $dataset"
    echo
}

backup_pve_config() {
    log "=== Backing up Proxmox VE configuration ==="
    
    local pve_backup_dir="/dpool/backup/pve-config"
    mkdir -p "$pve_backup_dir"
    
    # Database dump using sqlite3
    local db_dump="$pve_backup_dir/config.dump.${TIMESTAMP}.sql"
    log "Creating database dump: $db_dump"
    
    sqlite3 <<EOF > "$db_dump"
.open --readonly /var/lib/pve-cluster/config.db
.dump
EOF
    
    # Create tarball of entire pve-cluster directory
    local tar_backup="$pve_backup_dir/pve-cluster.${TIMESTAMP}.tar.gz"
    log "Creating tarball backup: $tar_backup"
    
    tar -czf "$tar_backup" -C /var/lib pve-cluster/
    
    # Get sizes
    local db_size=$(du -h "$db_dump" | cut -f1)
    local tar_size=$(du -h "$tar_backup" | cut -f1)
    
    log "Database dump completed: $db_size"
    log "Tarball backup completed: $tar_size"
    
    # Cleanup old backups (keep last 30)
    log "Cleaning up old PVE config backups..."
    cd "$pve_backup_dir"
    ls -t config.dump.*.sql 2>/dev/null | tail -n +31 | xargs -r rm -f
    ls -t pve-cluster.*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm -f
    
    log "PVE configuration backup completed"
}

show_summary() {
    log "=== Backup Summary ==="
    
    for dataset in "${ZFS_DATASETS[@]}"; do
        local dataset_safe=$(echo "$dataset" | tr '/' '_')
        local backup_dir="$BACKUP_BASE/$dataset_safe"
        
        if [[ -d "$backup_dir" ]]; then
            local file_count=$(ls -1 "$backup_dir"/*.zfs.zst 2>/dev/null | wc -l)
            local total_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
            log "$dataset: $file_count backup files, $total_size total"
        fi
    done
    
    # PVE config summary
    local pve_backup_dir="/dpool/backup/pve-config"
    if [[ -d "$pve_backup_dir" ]]; then
        local pve_files=$(ls -1 "$pve_backup_dir"/*.{sql,tar.gz} 2>/dev/null | wc -l)
        local pve_size=$(du -sh "$pve_backup_dir" 2>/dev/null | cut -f1)
        log "PVE Config: $pve_files backup files, $pve_size total"
    fi
    
    local grand_total=$(du -sh "$BACKUP_BASE" "/dpool/backup/pve-config" 2>/dev/null | tail -1 | cut -f1)
    log "Total backup storage used: $grand_total"
}

main() {
    log "Starting ZFS backup process"
    log "Backup location: $BACKUP_BASE"
    
    # Create base backup directory
    mkdir -p "$BACKUP_BASE"
    
    local failed_datasets=()
    
    # Backup each dataset
    for dataset in "${ZFS_DATASETS[@]}"; do
        if backup_zfs_dataset "$dataset"; then
            log "✓ Success: $dataset"
        else
            log "✗ Failed: $dataset"
            failed_datasets+=("$dataset")
        fi
    done
    
    # Backup PVE configuration
    backup_pve_config
    
    show_summary
    
    if [[ ${#failed_datasets[@]} -eq 0 ]]; then
        log "All ZFS backups completed successfully"
        exit 0
    else
        log "Failed datasets: ${failed_datasets[*]}"
        exit 1
    fi
}

# Execute main function
main "$@"