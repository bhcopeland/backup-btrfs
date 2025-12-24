#!/bin/bash
set -euo pipefail

# Rclone setup helper script for Google Drive with encryption

echo "=== Rclone Google Drive + Encryption Setup ==="
echo

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "Installing rclone..."
    curl https://rclone.org/install.sh | sudo bash
fi

echo "Setting up rclone configuration..."
echo "You'll need to configure two remotes:"
echo "1. 'gdrive' - Plain Google Drive remote"
echo "2. 'gdrive-crypt' - Encrypted wrapper around 'gdrive'"
echo

# Step 1: Configure Google Drive remote
echo "=== Step 1: Configure Google Drive Remote ==="
echo "When prompted:"
echo "- Name: gdrive"
echo "- Storage: drive (Google Drive)"
echo "- Use default settings and authorize via browser"
echo
read -p "Press Enter to start rclone config for Google Drive..."
rclone config create gdrive drive

echo
echo "=== Step 2: Configure Encryption Remote ==="
echo "This will encrypt your backups before uploading to Google Drive"
echo "When prompted:"
echo "- Name: gdrive-crypt"
echo "- Storage: crypt"
echo "- Remote: gdrive:backups/encrypted"
echo "- Filename encryption: standard"
echo "- Directory name encryption: true"
echo "- Choose a strong password for encryption!"
echo
read -p "Press Enter to start rclone config for encryption..."
rclone config create gdrive-crypt crypt remote gdrive:backups/encrypted

echo
echo "=== Setup Complete! ==="
echo

# Test the configuration
echo "Testing configuration..."
echo "Creating test file..."
echo "Test backup file $(date)" > /tmp/test-backup.txt

echo "Uploading test file..."
rclone copy /tmp/test-backup.txt gdrive-crypt:test/

echo "Listing encrypted files on Google Drive..."
rclone ls gdrive-crypt:test/

echo "Downloading and verifying test file..."
rclone copy gdrive-crypt:test/test-backup.txt /tmp/test-download.txt
if diff /tmp/test-backup.txt /tmp/test-download.txt; then
    echo "✅ Encryption/decryption test successful!"
else
    echo "❌ Test failed!"
    exit 1
fi

# Cleanup
rm -f /tmp/test-backup.txt /tmp/test-download.txt
rclone delete gdrive-crypt:test/

echo
echo "=== Configuration Summary ==="
echo "• Google Drive remote: gdrive"
echo "• Encrypted remote: gdrive-crypt"
echo "• Backup location: gdrive:backups/encrypted"
echo "• Files will be encrypted before upload"
echo
echo "Your rclone-backup-upload.sh script is ready to use!"
echo "Run: chmod +x rclone-backup-upload.sh"