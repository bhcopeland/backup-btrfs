#!/bin/bash
set -euo pipefail

# Setup script for rclone with Google Drive and encryption

echo "=== Rclone Google Drive + Encryption Setup ==="
echo "This script will configure rclone for encrypted backups to Google Drive"
echo

# Install rclone if not present
if ! command -v rclone &> /dev/null; then
    echo "Installing rclone..."
    curl https://rclone.org/install.sh | bash
    echo "✓ Rclone installed"
else
    echo "✓ Rclone already installed: $(rclone version | head -1)"
fi

echo
echo "=== Step 1: Configure Google Drive Remote ==="
echo "Follow these steps when rclone config starts:"
echo "1. Choose 'n' for new remote"
echo "2. Name: gdrive"
echo "3. Storage type: drive (Google Drive)"
echo "4. Leave client_id and client_secret empty (press Enter)"
echo "5. Choose 'N' for advanced config"
echo "6. Choose 'Y' for auto config (will open browser)"
echo "7. Authorize in your browser"
echo "8. Choose 'N' for team drive"
echo "9. Choose 'Y' to confirm"
echo

read -p "Press Enter to configure Google Drive remote..."
rclone config

echo
echo "=== Step 2: Configure Encryption Remote ==="
echo "Now we'll create an encrypted wrapper around your Google Drive"
echo "Follow these steps:"
echo "1. Choose 'n' for new remote"
echo "2. Name: gdrive-crypt"
echo "3. Storage type: crypt"
echo "4. Remote: gdrive:backups/encrypted"
echo "5. Filename encryption: 1 (standard)"
echo "6. Directory name encryption: 1 (true)"
echo "7. Password: [CHOOSE A STRONG PASSWORD - WRITE IT DOWN!]"
echo "8. Confirm password"
echo "9. Salt: [CHOOSE A STRONG SALT - WRITE IT DOWN!]"
echo "10. Choose 'Y' to confirm"
echo

read -p "Press Enter to configure encryption remote..."
rclone config

echo
echo "=== Step 3: Testing Configuration ==="

# Test basic connectivity
echo "Testing Google Drive connection..."
if rclone lsd gdrive: --max-depth 1 &>/dev/null; then
    echo "✓ Google Drive connection successful"
else
    echo "✗ Google Drive connection failed"
    exit 1
fi

# Test encryption
echo "Testing encryption..."
echo "Test file created $(date)" > /tmp/rclone-test.txt
rclone copy /tmp/rclone-test.txt gdrive-crypt:test/

echo "Verifying encrypted upload..."
if rclone ls gdrive:backups/encrypted/test/ | grep -q "rclone-test.txt"; then
    echo "✓ File uploaded and encrypted successfully"
    
    # Test download and decryption
    rclone copy gdrive-crypt:test/rclone-test.txt /tmp/rclone-test-download.txt
    if diff /tmp/rclone-test.txt /tmp/rclone-test-download.txt &>/dev/null; then
        echo "✓ Encryption/decryption test passed"
    else
        echo "✗ Encryption/decryption test failed"
        exit 1
    fi
else
    echo "✗ Encrypted upload test failed"
    exit 1
fi

# Cleanup test files
rm -f /tmp/rclone-test*.txt
rclone delete gdrive-crypt:test/

echo
echo "=== Configuration Complete! ==="
echo
echo "Your rclone remotes:"
echo "• gdrive - Direct Google Drive access"
echo "• gdrive-crypt - Encrypted Google Drive access"
echo
echo "Files will be stored at: gdrive:backups/encrypted (encrypted)"
echo "Backup script will use: gdrive-crypt remote"
echo
echo "IMPORTANT: Save your encryption password and salt in a secure location!"
echo "Without them, you cannot decrypt your backups!"
echo
echo "Test your configuration:"
echo "  rclone ls gdrive-crypt:"
echo "  rclone about gdrive-crypt:"
echo
echo "Your backup script is ready to use!"