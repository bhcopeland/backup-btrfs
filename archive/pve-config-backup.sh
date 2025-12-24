#!/bin/bash
set -euo pipefail

# Proxmox VE configuration backup script
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_DIR="/dpool/backup/pve-config"
LOG_FILE="/var/log/pve-config-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

backup_pve_config() {
    log "=== Backing up Proxmox VE configuration ==="
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Database dump using sqlite3
    local db_dump="$BACKUP_DIR/config.dump.${TIMESTAMP}.sql"
    log "Creating database dump: $db_dump"
    
    sqlite3 <<EOF > "$db_dump"
.open --readonly /var/lib/pve-cluster/config.db
.dump
EOF
    
    # Create tarball of entire pve-cluster directory
    local tar_backup="$BACKUP_DIR/pve-cluster.${TIMESTAMP}.tar.gz"
    log "Creating tarball backup: $tar_backup"
    
    tar -czf "$tar_backup" -C /var/lib pve-cluster/
    
    # Get sizes
    local db_size=$(du -h "$db_dump" | cut -f1)
    local tar_size=$(du -h "$tar_backup" | cut -f1)
    
    log "Database dump completed: $db_size"
    log "Tarball backup completed: $tar_size"
    
    # Cleanup old backups (keep last 30)
    log "Cleaning up old backups..."
    cd "$BACKUP_DIR"
    ls -t config.dump.*.sql 2>/dev/null | tail -n +31 | xargs -r rm -f
    ls -t pve-cluster.*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm -f
    
    log "PVE configuration backup completed"
}

# Execute backup
backup_pve_config