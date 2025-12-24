# Backup Restore Guide

## Btrfs Backups (Compressed)

### 1. List Available Backups

```bash
# Check what backups are available on the server
ssh bhcopeland@192.168.0.241 "ls -la /mnt/backup/pickles/home/"
```

### 2. Restore from Full Backup (Compressed)

```bash
# Copy the compressed full backup file from server
scp bhcopeland@192.168.0.241:/mnt/backup/pickles/home/full_YYYYMMDD_HHMMSS.btrfs.zst /tmp/

# Decompress and restore the subvolume
zstd -d < /tmp/full_YYYYMMDD_HHMMSS.btrfs.zst | sudo btrfs receive /restore_location/

# The restored subvolume will be at /restore_location/home_YYYYMMDD_HHMMSS
```

### 3. Restore from Incremental Chain (Compressed)

**Important**: You need ALL files in the incremental chain, starting from the full backup.

```bash
# Example restore chain: full -> incremental1 -> incremental2

# 1. Apply full backup (decompressed)
zstd -d < /tmp/full_20250815_100000.btrfs.zst | sudo btrfs receive /restore_location/

# 2. Apply first incremental (creates new snapshot)
zstd -d < /tmp/incremental_20250815_110000.btrfs.zst | sudo btrfs receive /restore_location/

# 3. Apply second incremental (creates newest snapshot)
zstd -d < /tmp/incremental_20250815_120000.btrfs.zst | sudo btrfs receive /restore_location/

# The latest state is in the most recent snapshot
```

## 4. Quick Restore Script

```bash
#!/bin/bash
# restore-home.sh

BACKUP_DATE="$1"  # e.g., 20250815_100000
RESTORE_PATH="/mnt/restore"

if [[ -z "$BACKUP_DATE" ]]; then
    echo "Usage: $0 YYYYMMDD_HHMMSS"
    echo "Example: $0 20250815_100000"
    exit 1
fi

# Create restore location
sudo mkdir -p "$RESTORE_PATH"

# Copy and restore full backup (compressed)
echo "Restoring full backup..."
scp bhcopeland@192.168.0.241:/mnt/backup/pickles/home/full_${BACKUP_DATE}.btrfs.zst /tmp/
zstd -d < /tmp/full_${BACKUP_DATE}.btrfs.zst | sudo btrfs receive "$RESTORE_PATH"

# Find and apply any incremental backups after this date
echo "Looking for incremental backups..."
ssh bhcopeland@192.168.0.241 "ls /mnt/backup/pickles/home/incremental_*.btrfs.zst" | \
    grep -E "incremental_${BACKUP_DATE:0:8}_[0-9_]+\.btrfs\.zst" | \
    sort | while read backup; do

    echo "Applying incremental: $(basename $backup)"
    scp "bhcopeland@192.168.0.241:$backup" /tmp/
    zstd -d < "/tmp/$(basename $backup)" | sudo btrfs receive "$RESTORE_PATH"
done

echo "Restore completed to $RESTORE_PATH"
ls -la "$RESTORE_PATH"
```

## 5. Emergency Recovery (Latest Backup)

```bash
# Get the most recent backup
LATEST=$(ssh bhcopeland@192.168.0.241 "ls -t /mnt/backup/pickles/home/*.btrfs.zst | head -1")
echo "Latest backup: $LATEST"

# Download and restore (decompressed)
scp "bhcopeland@192.168.0.241:$LATEST" /tmp/latest_backup.btrfs.zst
sudo mkdir -p /emergency_restore
zstd -d < /tmp/latest_backup.btrfs.zst | sudo btrfs receive /emergency_restore
```

## 6. Mount Restored Subvolume

```bash
# After restore, you can mount the subvolume
sudo mount -o subvol=home_YYYYMMDD_HHMMSS /dev/your_disk /mnt/restored_home

# Or copy files back to original location
sudo cp -a /restore_location/home_YYYYMMDD_HHMMSS/* /home/
```

## ZFS Backups (Compressed)

### List Available ZFS Backups

```bash
# Check ZFS backups on seedbox
ssh bhcopeland@192.168.0.241 "ls -la /mnt/backup/zfs-snapshots/dpool_Photos/"
ssh bhcopeland@192.168.0.241 "ls -la /mnt/backup/zfs-snapshots/rpool_opt_data/"
```

### Restore ZFS Full Backup

```bash
# Copy compressed full backup
scp bhcopeland@192.168.0.241:/mnt/backup/zfs-snapshots/dpool_Photos/full_YYYYMMDD_HHMMSS.zfs.zst /tmp/

# Decompress and restore (creates the dataset)
zstd -d < /tmp/full_YYYYMMDD_HHMMSS.zfs.zst | sudo zfs receive tank/restored_photos
```

### Restore ZFS Incremental Chain

**Important**: Must apply full backup first, then incrementals in order.

```bash
# 1. Apply full backup
zstd -d < /tmp/full_20251101_121750.zfs.zst | sudo zfs receive tank/restored_data

# 2. Apply incremental (updates the dataset)
zstd -d < /tmp/incremental_20251208_004533.zfs.zst | sudo zfs receive tank/restored_data

# The dataset is now at the incremental state
```

## Notes:
- Always restore to a DIFFERENT location first to avoid overwriting current data
- Incremental backups must be applied in chronological order
- Btrfs: Each restore creates a new timestamped subvolume
- ZFS: Incrementals update the existing dataset
- Test restores periodically to ensure backups are working
- All backups are compressed with zstd - decompress during restore