#!/bin/bash

# ============================================
# Zabbix + MariaDB Complete Uninstaller
# For Raspberry Pi OS (Debian-based)
# ============================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

log "=== Starting Zabbix + MariaDB Complete Uninstallation ==="

# Step 1: Stop all services
log "Stopping services..."
systemctl stop zabbix-server zabbix-agent apache2 nginx mariadb mysql 2>/dev/null || true
systemctl disable zabbix-server zabbix-agent apache2 nginx mariadb mysql 2>/dev/null || true

# Step 2: Remove Zabbix repository (if exists)
log "Removing Zabbix repository..."
rm -f /etc/apt/sources.list.d/zabbix*
rm -f /etc/apt/trusted.gpg.d/zabbix*

# Step 3: Update package lists
log "Updating package lists..."
apt update

# Step 4: Get all Zabbix packages
ZABBIX_PKGS=$(dpkg -l | grep zabbix | awk '{print $2}' || true)

# Step 5: Remove Zabbix packages
log "Removing Zabbix packages: $ZABBIX_PKGS"
if [[ -n "$ZABBIX_PKGS" ]]; then
    apt remove --purge -y $ZABBIX_PKGS
else
    warn "No Zabbix packages found"
fi

# Step 6: Remove MariaDB/MySQL packages
log "Removing MariaDB/MySQL packages..."
MARIADB_PKGS="mariadb-server mariadb-client mysql-server mysql-client"
apt remove --purge -y $MARIADB_PKGS 2>/dev/null || true

# Step 7: Drop Zabbix database (if MariaDB still running)
log "Dropping Zabbix database..."
if systemctl is-active --quiet mariadb; then
    mysql -u root -e "DROP DATABASE IF EXISTS zabbix; DROP USER IF EXISTS zabbix@localhost; FLUSH PRIVILEGES;" 2>/dev/null || true
fi

# Step 8: Clean all configs, data, logs
log "Removing configuration files and data..."
rm -rf /etc/zabbix/
rm -rf /usr/share/zabbix/
rm -rf /var/lib/zabbix/
rm -rf /var/log/zabbix/
rm -rf /var/www/html/zabbix/
rm -rf /var/lib/mysql/zabbix*  # Only Zabbix DB files
rm -rf /tmp/zabbix*

# Step 9: Apache/Nginx Zabbix configs
rm -f /etc/apache2/sites-enabled/zabbix.conf
rm -f /etc/nginx/sites-enabled/zabbix
rm -f /etc/apache2/conf-available/zabbix.conf
rm -f /etc/nginx/conf.d/zabbix.conf

# Step 10: Autoremove dependencies
log "Removing unused dependencies..."
apt autoremove --purge -y
apt autoclean
apt clean

# Step 11: Fix any broken packages
log "Fixing broken packages..."
dpkg --configure -a
apt update --fix-missing

# Step 12: Verification
log "=== VERIFICATION ==="
log "Checking for remaining packages..."
REMAINING=$(dpkg -l | grep -E "(zabbix|mariadb|mysql)" | wc -l)
if [[ $REMAINING -eq 0 ]]; then
    log "✓ All packages removed successfully!"
else
    warn "⚠ $REMAINING packages still detected:"
    dpkg -l | grep -E "(zabbix|mariadb|mysql)"
fi

log "Checking services..."
for svc in zabbix-server zabbix-agent mariadb; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        warn "⚠ Service $svc is still active!"
    else
        log "✓ Service $svc stopped"
    fi
done

log "Checking directories..."
for dir in /etc/zabbix /var/lib/zabbix /var/log/zabbix; do
    if [[ -d "$dir" ]]; then
        warn "⚠ Directory $dir still exists!"
    else
        log "✓ Directory $dir removed"
    fi
done

log "=== UNINSTALLATION COMPLETE! ==="
log "System is now clean. You can reinstall Zabbix if needed."
log "Run 'apt update' before any new installations."

exit 0
