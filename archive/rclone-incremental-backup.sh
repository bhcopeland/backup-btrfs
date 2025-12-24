#!/bin/bash
set -euo pipefail

# Minimal rclone backup script - memory optimized
SOURCE_DIR="/mnt/backup"
RCLONE_REMOTE="gstorage"
LOG_FILE="/var/log/rclone-backup.log"
STATE_DIR="/var/lib/rclone-backup"
LAST_SYNC_FILE="$STATE_DIR/last_sync_time"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

setup_state_directory() {
    mkdir -p "$STATE_DIR"
    if [[ ! -f "$LAST_SYNC_FILE" ]]; then
        echo "1970-01-01 00:00:00" > "$LAST_SYNC_FILE"
        log "Initialized last sync time file"
    fi
}

update_last_sync_time() {
    date '+%Y-%m-%d %H:%M:%S' > "$LAST_SYNC_FILE"
}

perform_sync() {
    local last_sync=$(cat "$LAST_SYNC_FILE" 2>/dev/null || echo "1970-01-01 00:00:00")
    log "Starting sync (last sync: $last_sync)"
    
    if [[ ! -d "$SOURCE_DIR" ]]; then
        error_exit "Source directory not found: $SOURCE_DIR"
    fi
    
    log "Syncing $SOURCE_DIR to $RCLONE_REMOTE (encrypted)"
    
    # Minimal rclone sync with very conservative settings
    rclone sync "$SOURCE_DIR/" "$RCLONE_REMOTE:" \
        --transfers 1 \
        --checkers 1 \
        --stats 2m \
        --stats-one-line \
        --buffer-size 8M \
        --timeout 10m \
        --retries 3 \
        --low-level-retries 3 \
        --exclude "**/.DS_Store" \
        --exclude "**/Thumbs.db" \
        --exclude "**/.tmp/" \
        --exclude "**/lost+found/" \
        --log-level ERROR \
        --log-file "$LOG_FILE.rclone" \
        || error_exit "Rclone sync failed"
    
    update_last_sync_time
    log "Sync completed successfully"
}

show_basic_stats() {
    local local_size=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    local last_sync=$(cat "$LAST_SYNC_FILE" 2>/dev/null || echo "never")
    
    log "=== Basic Statistics ==="
    log "Local backup size: $local_size"
    log "Last successful sync: $last_sync"
}

main() {
    log "Starting minimal rclone backup"
    log "Source: $SOURCE_DIR"
    log "Remote: $RCLONE_REMOTE (encrypted)"
    
    setup_state_directory
    perform_sync
    show_basic_stats
    
    log "Backup process completed"
}

# Execute main function
main "$@"