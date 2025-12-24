#!/bin/bash
set -euo pipefail

# Chunked rclone backup - sync directories one at a time to avoid OOM
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

sync_directory() {
    local subdir="$1"
    local source_path="$SOURCE_DIR/$subdir"
    local remote_path="$RCLONE_REMOTE:$subdir"

    # Skip dump/dumps directories entirely
    if [[ "$subdir" == "dump" || "$subdir" == "dumps" ]]; then
        log "Skipping excluded directory: $subdir"
        return 0
    fi

    if [[ ! -d "$source_path" ]]; then
        log "Skipping non-existent directory: $subdir"
        return 0
    fi

    # Check if this directory contains btrfs backup files (both .btrfs and .btrfs.zst)
    local btrfs_files=($(ls -1t "$source_path"/*.btrfs.zst "$source_path"/*.btrfs 2>/dev/null || true))

    # Check if this directory contains ZFS backup files (both .zfs and .zfs.zst)
    local zfs_full=($(ls -1t "$source_path"/full_*.zfs.zst "$source_path"/full_*.zfs 2>/dev/null || true))
    local zfs_incremental=($(ls -1t "$source_path"/incremental_*.zfs.zst "$source_path"/incremental_*.zfs 2>/dev/null || true))

    # Check if this directory has subdirectories with backups instead
    local has_backup_subdirs=false
    if [[ ${#btrfs_files[@]} -eq 0 && ${#zfs_full[@]} -eq 0 && ${#zfs_incremental[@]} -eq 0 ]]; then
        # No backup files directly in this dir, check if subdirs have backups
        while IFS= read -r -d '' subsubdir; do
            local subsubdir_name=$(basename "$subsubdir")
            if [[ -n "$(ls -1 "$subsubdir"/*.{btrfs,btrfs.zst,zfs} 2>/dev/null)" ]]; then
                has_backup_subdirs=true
                log "Found backup subdirectory: $subdir/$subsubdir_name"
                sync_directory "$subdir/$subsubdir_name"
            fi
        done < <(find "$source_path" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)

        if [[ "$has_backup_subdirs" == "true" ]]; then
            return 0
        fi
    fi

    if [[ ${#btrfs_files[@]} -gt 0 ]]; then
        # Only sync oldest and newest backups to gdrive
        local newest="${btrfs_files[0]}"
        local oldest="${btrfs_files[-1]}"

        local newest_name=$(basename "$newest")
        local oldest_name=$(basename "$oldest")

        if [[ "$newest_name" == "$oldest_name" ]]; then
            log "Syncing directory: $subdir (1 backup: $newest_name)"
        else
            log "Syncing directory: $subdir (oldest: $oldest_name, newest: $newest_name)"
        fi

        # Build filter arguments (use --filter instead of --include/--exclude)
        local filter_args=(--filter "+ $newest_name")
        if [[ "$newest_name" != "$oldest_name" ]]; then
            filter_args+=(--filter "+ $oldest_name")
        fi
        filter_args+=(--filter "- *")

        # Sync only the selected backups (deletes old ones from gdrive)
        rclone sync "$source_path/" "$remote_path/" \
            "${filter_args[@]}" \
            --transfers 1 \
            --checkers 1 \
            --buffer-size 4M \
            --timeout 30m \
            --retries 10 \
            --retries-sleep 60s \
            --low-level-retries 10 \
            --tpslimit 8 \
            --drive-use-trash=false \
            --log-level NOTICE \
            --stats 5m \
            --stats-one-line \
            || {
                log "WARNING: Failed to sync $subdir"
                return 1
            }
    elif [[ ${#zfs_full[@]} -gt 0 || ${#zfs_incremental[@]} -gt 0 ]]; then
        # ZFS backups: keep oldest+newest full + oldest+newest incrementals
        local filter_args=()
        local keep_info=""

        # Include oldest and newest full backups
        if [[ ${#zfs_full[@]} -gt 0 ]]; then
            local newest_full=$(basename "${zfs_full[0]}")
            local oldest_full=$(basename "${zfs_full[-1]}")

            filter_args+=(--filter "+ $newest_full")
            if [[ "$newest_full" != "$oldest_full" ]]; then
                filter_args+=(--filter "+ $oldest_full")
                keep_info="full: $oldest_full + $newest_full"
            else
                keep_info="full: $oldest_full"
            fi
        fi

        # Include oldest and newest incrementals
        if [[ ${#zfs_incremental[@]} -gt 0 ]]; then
            local newest_inc=$(basename "${zfs_incremental[0]}")
            local oldest_inc=$(basename "${zfs_incremental[-1]}")

            filter_args+=(--filter "+ $newest_inc")
            if [[ "$newest_inc" != "$oldest_inc" ]]; then
                filter_args+=(--filter "+ $oldest_inc")
                keep_info="$keep_info, inc: $oldest_inc + $newest_inc"
            else
                keep_info="$keep_info, inc: $oldest_inc"
            fi
        fi

        filter_args+=(--filter "- *")
        log "Syncing directory: $subdir ($keep_info)"

        # Sync only the selected backups (deletes old ones from gdrive)
        rclone sync "$source_path/" "$remote_path/" \
            "${filter_args[@]}" \
            --transfers 1 \
            --checkers 1 \
            --buffer-size 4M \
            --timeout 30m \
            --retries 10 \
            --retries-sleep 60s \
            --low-level-retries 10 \
            --tpslimit 8 \
            --drive-use-trash=false \
            --log-level NOTICE \
            --stats 5m \
            --stats-one-line \
            || {
                log "WARNING: Failed to sync $subdir"
                return 1
            }
    else
        # No backup files - sync entire directory normally
        local dir_size=$(du -sh "$source_path" 2>/dev/null | cut -f1 || echo "unknown")
        log "Syncing directory: $subdir ($dir_size)"

        rclone sync "$source_path/" "$remote_path/" \
            --transfers 1 \
            --checkers 1 \
            --buffer-size 4M \
            --timeout 30m \
            --retries 10 \
            --retries-sleep 60s \
            --low-level-retries 10 \
            --tpslimit 8 \
            --delete-after \
            --drive-use-trash=false \
            --exclude "**/.DS_Store" \
            --exclude "**/Thumbs.db" \
            --exclude "**/.tmp/" \
            --exclude "**/dump/**" \
            --exclude "**/dumps/**" \
            --log-level NOTICE \
            --stats 5m \
            --stats-one-line \
            || {
                log "WARNING: Failed to sync $subdir"
                return 1
            }

        # Run dedupe only for non-btrfs directories
        log "Cleaning up duplicates for $subdir..."
        rclone dedupe "$remote_path/" --dedupe-mode newest --log-level ERROR || true
    fi

    log "Completed: $subdir"
    return 0
}

perform_chunked_sync() {
    local last_sync=$(cat "$LAST_SYNC_FILE" 2>/dev/null || echo "1970-01-01 00:00:00")
    log "Starting chunked sync (last sync: $last_sync)"

    if [[ ! -d "$SOURCE_DIR" ]]; then
        error_exit "Source directory not found: $SOURCE_DIR"
    fi

    local failed_dirs=()
    local success_count=0

    # Get list of subdirectories to sync
    local subdirs=()
    while IFS= read -r -d '' dir; do
        local dirname=$(basename "$dir")
        subdirs+=("$dirname")
    done < <(find "$SOURCE_DIR" -maxdepth 1 -type d -not -path "$SOURCE_DIR" -print0 2>/dev/null || true)

    # Also sync any files in the root directory
    local root_files=$(find "$SOURCE_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l || echo 0)
    if [[ $root_files -gt 0 ]]; then
        log "Syncing root files..."
        if rclone sync "$SOURCE_DIR/" "$RCLONE_REMOTE:" \
            --transfers 1 \
            --checkers 1 \
            --buffer-size 4M \
            --timeout 10m \
            --retries 10 \
            --retries-sleep 60s \
            --low-level-retries 10 \
            --tpslimit 8 \
            --drive-use-trash=false \
            --exclude "*/" \
            --log-level NOTICE \
            --stats-one-line; then
            log "✓ Root files synced"
            ((success_count++))
        else
            log "WARNING: Failed to sync root files"
            failed_dirs+=("root-files")
        fi
    fi

    # Sync each subdirectory
    for subdir in "${subdirs[@]}"; do
        log "Processing directory $((success_count + ${#failed_dirs[@]} + 1))/${#subdirs[@]}: $subdir"

        if sync_directory "$subdir"; then
            ((success_count++))
        else
            failed_dirs+=("$subdir")
        fi

        # Small delay between directories to let system recover
        sleep 2
    done

    # Summary
    log "=== Sync Summary ==="
    log "Successful: $success_count directories"
    log "Failed: ${#failed_dirs[@]} directories"

    if [[ ${#failed_dirs[@]} -gt 0 ]]; then
        log "Failed directories: ${failed_dirs[*]}"
        return 1
    fi

    return 0
}

show_basic_stats() {
    local local_size=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    local last_sync=$(cat "$LAST_SYNC_FILE" 2>/dev/null || echo "never")

    log "=== Statistics ==="
    log "Local backup size: $local_size"
    log "Last successful sync: $last_sync"
}

main() {
    log "Starting chunked rclone backup"
    log "Source: $SOURCE_DIR"
    log "Remote: $RCLONE_REMOTE (encrypted)"

    setup_state_directory

    if perform_chunked_sync; then
        update_last_sync_time
        log "All directories synced successfully"
        show_basic_stats
        log "Backup process completed successfully"
    else
        log "Some directories failed to sync - check logs above"
        show_basic_stats
        exit 1
    fi
}

# Execute main function
main "$@"
