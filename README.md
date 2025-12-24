# Backup System

Unified backup solution for btrfs and ZFS with encrypted offsite storage on Google Drive.

## Configuration

**Before using, update these values in the scripts:**
- `simple-btrfs-backup.sh`: Set `SSH_HOST` and `SSH_USER` for your backup server
- `zfs-only-backup.sh`: Adjust `ZFS_DATASETS` and `BACKUP_BASE` for your setup
- `rclone-chunked-backup.sh`: Set `SOURCE_DIR` and `RCLONE_REMOTE`

## Active Scripts

### Local Backup Scripts

**simple-btrfs-backup.sh**
- Backs up btrfs `/home` subvolume to ZFS server (192.168.0.241)
- Creates compressed `.btrfs.zst` files using zstd
- Supports incremental backups
- Keeps 8 local snapshots + 8 remote backups

**zfs-only-backup.sh** (runs on Proxmox server)
- Backs up ZFS datasets: dpool/Photos, rpool/opt_data, container subvols
- Creates compressed `.zfs.zst` files using zstd
- Keeps 2 full backups + 10 incrementals + 5 snapshots
- Stores to `/dpool/backup/zfs-snapshots/`

### Offsite Sync (runs on seedbox)

**rclone-chunked-backup.sh**
- Syncs `/mnt/backup` to Google Drive (encrypted with rclone crypt)
- Smart filtering: keeps only oldest + newest backups
- Btrfs: oldest + newest `.btrfs.zst`
- ZFS: oldest+newest full + oldest+newest incrementals
- Rate limited to avoid Google API limits
- Excludes Proxmox backups (dump/)

### Systemd Units

**rclone-backup.service**
- Runs rclone-chunked-backup.sh
- Restarts on failure with 1-hour delay
- Memory limited to 2GB

**rclone-backup.timer**
- Triggers daily at 4 AM
- Enable: `systemctl enable --now rclone-backup.timer`

## Deployment

### Proxmox Server (homebox)
```bash
scp zfs-only-backup.sh root@homebox:/root/
```

### Seedbox
```bash
scp rclone-chunked-backup.sh bhcopeland@192.168.0.241:/tmp/seedbox/
scp rclone-backup.{service,timer} bhcopeland@192.168.0.241:/tmp/
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
