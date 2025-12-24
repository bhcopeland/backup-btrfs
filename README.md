# Backup System

Unified backup solution for btrfs and ZFS with encrypted offsite storage on Google Drive.

## Configuration

**Before using, update these values in the scripts:**
- `simple-btrfs-backup.sh`: Set `SSH_HOST` and `SSH_USER` for your backup server
- `zfs-only-backup.sh`: Adjust `ZFS_DATASETS` and `BACKUP_BASE` for your setup
- `rclone-chunked-backup.sh`: Set `SOURCE_DIR` and `RCLONE_REMOTE`

## Directory Structure

Scripts are organized by which host they run on:

```
backup-btrfs/
├── desktop/      # Scripts for desktop (btrfs source)
├── proxmox/      # Scripts for Proxmox server
└── seedbox/      # Scripts for seedbox (cloud sync)
```

## Scripts by Host

### Desktop (btrfs source)

**desktop/simple-btrfs-backup.sh**
- Backs up btrfs `/home` subvolume to seedbox ZFS storage
- Creates compressed `.btrfs.zst` files using zstd
- Supports incremental backups
- Keeps 8 recent + first of month for 3 months

**Systemd units:**
- `btrfs-backup.service` - Runs the backup
- `btrfs-backup.timer` - Weekly schedule

### Proxmox (homebox server)

**proxmox/zfs-only-backup.sh**
- Backs up ZFS datasets: dpool/Photos, rpool/opt_data, container subvols
- Creates compressed `.zfs.zst` files using zstd
- Keeps 2 full backups + 10 incrementals + 5 snapshots
- Stores to `/dpool/backup/zfs-snapshots/`

### Seedbox (cloud sync VM)

**seedbox/rclone-chunked-backup.sh**
- Syncs `/mnt/backup` to Google Drive (encrypted with rclone crypt)
- Smart filtering: keeps only oldest + newest backups
- Btrfs: oldest + newest `.btrfs.zst`
- ZFS: oldest+newest full + oldest+newest incrementals
- Rate limited to avoid Google API limits
- Excludes Proxmox backups (dump/)

**Systemd units:**
- `rclone-backup.service` - Runs the sync
- `rclone-backup.timer` - Daily at 4 AM

## Deployment

**Quick Deploy (all hosts):**
```bash
./deploy.sh
```

**Deploy to specific hosts:**
```bash
./deploy.sh desktop    # Deploy to local desktop only
./deploy.sh seedbox    # Deploy to seedbox only
./deploy.sh proxmox    # Deploy to Proxmox only
```

**Verify deployment:**
```bash
# Desktop
systemctl status btrfs-backup.timer

# Seedbox
ssh bhcopeland@192.168.0.242 'sudo systemctl status rclone-backup.timer'

# Proxmox
ssh root@192.168.0.240 'systemctl status zfs-backup.timer'
```

## Storage Layout

```
/mnt/backup (seedbox) = /mnt/pve/backup-smb (homebox)
├── dump/              # Proxmox backups (local only, not synced to gdrive)
├── pickles/home/      # btrfs backups (synced to gdrive)
├── zfs-snapshots/     # ZFS backups (synced to gdrive)
│   ├── dpool_Photos/
│   ├── rpool_opt_data/
│   └── rpool_data_subvol-*/
└── pve-config/        # Proxmox config (synced to gdrive)
```

## Google Drive Storage

Remote: `gstorage` (crypt wrapper around `gdrive`)

**What gets uploaded:**
- Btrfs: oldest + newest only (saves space)
- ZFS: oldest+newest full + oldest+newest incrementals
- Total savings: ~70% reduction vs uploading all backups

## Restore

See [RESTORE_GUIDE.md](RESTORE_GUIDE.md) for detailed restore instructions.

## Setup

**Initial rclone setup:**
```bash
./setup-rclone-gdrive.sh
```

**Configure gdrive remote:**
```bash
rclone config update gdrive use_trash false
```

## Archive

Old/unused scripts are in `archive/` for reference.
