#!/bin/bash
set -euo pipefail

# Configuration
BACKUP_DIR="/mnt/backup/pickles"
RCLONE_REMOTE="gdrive-crypt"  # Your encrypted rclone remote
LOG_FILE="/var/log/rclone-backup-upload.log"
KEEP_DAYS=30  # Keep backups older than 30 days on Google Drive

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

upload_backup_files() {
    local subvol_dir="$1"
    local subvol_name=$(basename "$subvol_dir")
    
    log "Processing backup files in $subvol_dir"
    
    # Find .btrfs files that haven't been uploaded yet
    find "$subvol_dir" -name "*.btrfs" -type f | while read backup_file; do
        local filename=$(basename "$backup_file")
        local remote_path="backups/pickles/$subvol_name/$filename"
        
        # Check if file already exists on Google Drive
        if rclone lsf "$RCLONE_REMOTE:$remote_path" &>/dev/null; then
            log "File already uploaded: $filename"
            continue
        fi
        
        log "Uploading $filename ($(du -h "$backup_file" | cut -f1))..."
        
        # Upload with progress and verification
        if rclone copy "$backup_file" "$RCLONE_REMOTE:backups/pickles/$subvol_name/" \
            --progress \
            --checksum \
            --transfers 1 \
            --checkers 1; then
            log "Successfully uploaded: $filename"
            
            # Create a marker file to track upload completion
            touch "$backup_file.uploaded"
        else
            log "ERROR: Failed to upload $filename"
            return 1
        fi
    done
}

cleanup_old_backups() {
    log "Cleaning up old backups on Google Drive (older than $KEEP_DAYS days)"
    
    # Clean up old backups on Google Drive
    rclone delete "$RCLONE_REMOTE:backups/pickles/" \
        --min-age "${KEEP_DAYS}d" \
        --dry-run 2>&1 | tee -a "$LOG_FILE"
    
    # Uncomment the line below after testing to actually delete old files
    # rclone delete "$RCLONE_REMOTE:backups/pickles/" --min-age "${KEEP_DAYS}d"
}

main() {
    log "Starting backup upload to Google Drive"
    
    # Check if rclone remote is configured
    if ! rclone config show "$RCLONE_REMOTE" &>/dev/null; then
        log "ERROR: Rclone remote '$RCLONE_REMOTE' not configured"
        exit 1
    fi
    
    # Check if backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "ERROR: Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    local failed_uploads=()
    
    # Process each subvolume directory
    for subvol_dir in "$BACKUP_DIR"/*; do
        if [[ -d "$subvol_dir" ]]; then
            if ! upload_backup_files "$subvol_dir"; then
                failed_uploads+=("$(basename "$subvol_dir")")
            fi
        fi
    done
    
    # Clean up old backups (commented out by default for safety)
    # cleanup_old_backups
    
    if [[ ${#failed_uploads[@]} -eq 0 ]]; then
        log "All backup uploads completed successfully"
    else
        log "Failed uploads for: ${failed_uploads[*]}"
        exit 1
    fi
}

# Run main function
main "$@"