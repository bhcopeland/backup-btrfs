# ZFS Backup Restore Guide

## Backup Structure
Your backups are stored in `/dpool/backup/zfs-snapshots/` with this structure:

```
/dpool/backup/zfs-snapshots/
├── dpool_Photos/
│   ├── full_20250818_100000.zfs
│   └── incremental_20250818_110000.zfs
├── rpool_opt_data/
│   ├── full_20250818_100000.zfs
│   └── incremental_20250818_110000.zfs
├── rpool_data_subvol-100-disk-0/
├── rpool_data_subvol-101-disk-0/
└── rpool_data_subvol-102-disk-0/
```

## 1. List Available Backups

```bash
# See all backup directories
ls -la /dpool/backup/zfs-snapshots/

# List backups for specific dataset
ls -la /dpool/backup/zfs-snapshots/dpool_Photos/

# Show backup file sizes
du -sh /dpool/backup/zfs-snapshots/*/*.zfs
```

## 2. Restore Full Backup

```bash
# Example: Restore dpool/Photos to new dataset
zfs receive rpool/restored_photos < /dpool/backup/zfs-snapshots/dpool_Photos/full_20250818_100000.zfs

# Mount the restored dataset
zfs set mountpoint=/mnt/restored_photos rpool/restored_photos
```

## 3. Restore Incremental Chain

**Important**: Apply incremental backups in chronological order.

```bash
# 1. Start with full backup
zfs receive rpool/restored_photos < /dpool/backup/zfs-snapshots/dpool_Photos/full_20250818_100000.zfs

# 2. Apply incremental backups in order
zfs receive rpool/restored_photos < /dpool/backup/zfs-snapshots/dpool_Photos/incremental_20250818_110000.zfs
zfs receive rpool/restored_photos < /dpool/backup/zfs-snapshots/dpool_Photos/incremental_20250818_120000.zfs

# The dataset now contains the latest state
```

## 4. Quick Restore Script

```bash
#!/bin/bash
# restore-zfs.sh <dataset_name> <backup_date> [target_dataset]

DATASET_NAME="$1"       # e.g., dpool_Photos
BACKUP_DATE="$2"        # e.g., 20250818_100000
TARGET="${3:-restored_${DATASET_NAME}}"

BACKUP_DIR="/dpool/backup/zfs-snapshots/$DATASET_NAME"

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Error: Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "Restoring $DATASET_NAME from $BACKUP_DATE to $TARGET"

# Apply full backup
FULL_BACKUP="$BACKUP_DIR/full_${BACKUP_DATE}.zfs"
if [[ -f "$FULL_BACKUP" ]]; then
    echo "Applying full backup..."
    zfs receive "rpool/$TARGET" < "$FULL_BACKUP"
else
    echo "Error: Full backup not found: $FULL_BACKUP"
    exit 1
fi

# Apply incremental backups in order
ls "$BACKUP_DIR"/incremental_*.zfs 2>/dev/null | sort | while read inc_backup; do
    echo "Applying incremental: $(basename $inc_backup)"
    zfs receive "rpool/$TARGET" < "$inc_backup"
done

echo "Restore completed to rpool/$TARGET"
zfs list rpool/$TARGET
```

## 5. Emergency Recovery (Latest State)

```bash
# Find the most recent backup
LATEST_FULL=$(ls -t /dpool/backup/zfs-snapshots/dpool_Photos/full_*.zfs | head -1)
LATEST_INC=$(ls -t /dpool/backup/zfs-snapshots/dpool_Photos/incremental_*.zfs | head -1)

echo "Latest full: $LATEST_FULL"
echo "Latest incremental: $LATEST_INC"

# Restore latest state
zfs receive rpool/emergency_restore < "$LATEST_FULL"
if [[ -n "$LATEST_INC" ]]; then
    zfs receive rpool/emergency_restore < "$LATEST_INC"
fi
```

## 6. Verify Backup Integrity

```bash
# Check ZFS stream integrity
zfs send --dry-run rpool/opt_data@backup_20250818_100000

# Verify backup file can be read
zfs receive -nv rpool/test_restore < /dpool/backup/zfs-snapshots/rpool_opt_data/full_20250818_100000.zfs
```

## Dataset Mappings

Your datasets and their backup locations:

| Original Dataset | Backup Directory | Purpose |
|------------------|------------------|---------|
| `dpool/Photos` | `dpool_Photos/` | Photo storage |
| `rpool/opt_data` | `rpool_opt_data/` | Application data |
| `rpool/data/subvol-100-disk-0` | `rpool_data_subvol-100-disk-0/` | VM disk |
| `rpool/data/subvol-101-disk-0` | `rpool_data_subvol-101-disk-0/` | VM disk |
| `rpool/data/subvol-102-disk-0` | `rpool_data_subvol-102-disk-0/` | VM disk |

## Notes

- Always restore to a NEW dataset name to avoid conflicts
- ZFS incremental backups are very efficient - only changed blocks
- Test restores periodically to ensure backup integrity
- The backup script keeps 5 snapshots and 10 backup files per dataset