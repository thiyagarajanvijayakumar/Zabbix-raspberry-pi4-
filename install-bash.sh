#!/bin/bash

# =============================================================================
# ZABBIX 7.0 COMPLETE INSTALLATION SCRIPT FOR DEBIAN 13.1 (TRIXIE)
# Supports MySQL/MariaDB + ALL Dependencies
# Author: Zabbix Automation Script
# Date: October 2025
# =============================================================================

# COLORS FOR OUTPUT
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# CONFIGURATION VARIABLES
ZABBIX_VERSION="7.0"
DB_NAME="zabbix"
DB_USER="zabbix"
DB_PASS="ZabbixPass123!"  # CHANGE THIS IN PRODUCTION!
TIMEZONE="America/New_York"  # CHANGE TO YOUR TIMEZONE
ADMIN_EMAIL="admin@yourdomain.com"

# LOG FILE
LOG_FILE="/var/log/zabbix_install_$(date +%Y%m%d_%H%M%S).log"

# FUNCTIONS
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" | tee -a "$LOG_FILE"
}

# BANNER
clear
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                  ZABBIX 7.0 INSTALLER FOR DEBIAN 13.1                        ║
║                    MySQL/MariaDB + ALL DEPENDENCIES                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

# ROOT CHECK
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

log "Starting Zabbix $ZABBIX_VERSION installation on Debian 13.1..."

# =============================================================================
# 1. UPDATE SYSTEM
# =============================================================================
log "Updating system packages..."
apt update && apt upgrade -y || error "Failed to update system"
success "System updated"

# =============================================================================
# 2. INSTALL BASE PACKAGES
# =============================================================================
log "Installing base packages..."
apt install -y \
    wget curl gnupg2 software-properties-common apt-transport-https lsb-release \
    nano htop net-tools || error "Failed to install base packages"
success "Base packages installed"

# =============================================================================
# 3. INSTALL APACHE2 + PHP + ALL EXTENSIONS
# =============================================================================
log "Installing Apache2 + PHP + ALL Zabbix dependencies..."
apt install -y \
    apache2 \
    php libapache2-mod-php \
    php-mysql php-gd php-xml php-bcmath php-mbstring \
    php-ldap php-json php-ctype php-tokenizer php-curl \
    php-mysqli php-intl php-zip php-soap \
    php-readline php-xmlrpc php-imagick || error "Failed to install Apache/PHP"
success "Apache2 + PHP installed with all extensions"

# =============================================================================
# 4. INSTALL MARIA DB
# =============================================================================
log "Installing MariaDB 11.x..."
apt install -y mariadb-server mariadb-client || error "Failed to install MariaDB"
success "MariaDB installed"

# START MARIA DB
systemctl start mariadb
systemctl enable mariadb

# SECURE INSTALLATION
log "Securing MariaDB installation..."
mysql << EOF || error "MariaDB secure installation failed"
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE USER 'root'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
success "MariaDB secured"

# =============================================================================
# 5. ADD ZABBIX REPOSITORY
# =============================================================================
log "Adding Zabbix $ZABBIX_VERSION repository..."
wget -qO- https://repo.zabbix.com/zabbix-official-repo.key | gpg --dearmor -o /usr/share/keyrings/zabbix-archive-keyring.gpg || error "Failed to download GPG key"
echo "deb [signed-by=/usr/share/keyrings/zabbix-archive-keyring.gpg] https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/debian trixie main" > /etc/apt/sources.list.d/zabbix.list
apt update || error "Failed to update after adding Zabbix repo"
success "Zabbix repository added"

# =============================================================================
# 6. INSTALL ZABBIX PACKAGES
# =============================================================================
log "Installing Zabbix Server, Frontend, Agent..."
apt install -y \
    zabbix-server-mysql \
    zabbix-frontend-php \
    zabbix-nginx-conf \
    zabbix-apache-conf \
    zabbix-sql-scripts \
    zabbix-agent \
    zabbix-agent2 || error "Failed to install Zabbix packages"
success "Zabbix packages installed"

# =============================================================================
# 7. CREATE DATABASE
# =============================================================================
log "Creating Zabbix database..."
mysql -u root -p"$DB_PASS" << EOF || error "Failed to create database"
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
success "Zabbix database created"

# =============================================================================
# 8. IMPORT ZABBIX SCHEMA
# =============================================================================
log "Importing Zabbix schema..."
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -u $DB_USER -p"$DB_PASS" $DB_NAME || error "Failed to import schema"
success "Zabbix schema imported"

# =============================================================================
# 9. CONFIGURE ZABBIX SERVER
# =============================================================================
log "Configuring Zabbix Server..."
cat > /etc/zabbix/zabbix_server.conf << EOF
# Database
DBHost=localhost
DBName=$DB_NAME
DBUser=$DB_USER
DBPassword=$DB_PASS

# Cache sizes
CacheSize=32M
HistoryCacheSize=16M
TrendCacheSize=4M
ValueCacheSize=8M

# Timeouts
Timeout=4
EOF
success "Zabbix Server configured"

# =============================================================================
# 10. CONFIGURE PHP FOR ZABBIX
# =============================================================================
log "Configuring PHP for Zabbix..."
cat > /etc/zabbix/apache.conf << EOF
Alias /zabbix /usr/share/zabbix

<Directory "/usr/share/zabbix">
    Options FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory "/usr/share/zabbix/conf">
    Require all denied
</Directory>

<Directory "/usr/share/zabbix/app">
    Require all denied
</Directory>

<Directory "/usr/share/zabbix/include">
    Require all denied
</Directory>

<Directory "/usr/share/zabbix/local">
    Require all denied
</Directory>
EOF

# PHP CONFIG
cat >> /etc/php/*/apache2/php.ini << EOF

# Zabbix PHP Settings
max_execution_time = 300
memory_limit = 128M
post_max_size = 16M
upload_max_filesize = 2M
max_input_time = 300
date.timezone = $TIMEZONE
always_populate_raw_post_data = -1
EOF

# APACHE SITE CONFIG
cat > /etc/apache2/sites-available/zabbix.conf << EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /usr/share/zabbix

    <Directory "/usr/share/zabbix">
        Options FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/zabbix_error.log
    CustomLog \${APACHE_LOG_DIR}/zabbix_access.log combined
</VirtualHost>
EOF

a2ensite zabbix.conf
a2enmod rewrite
systemctl reload apache2
success "PHP and Apache configured"

# =============================================================================
# 11. START SERVICES
# =============================================================================
log "Starting and enabling services..."
systemctl restart zabbix-server zabbix-agent apache2 mariadb
systemctl enable zabbix-server zabbix-agent apache2 mariadb || error "Failed to enable services"
success "All services started and enabled"

# =============================================================================
# 12. FIREWALL CONFIGURATION
# =============================================================================
log "Configuring firewall..."
ufw allow 80/tcp comment "Zabbix Web Interface"
ufw allow 10050/tcp comment "Zabbix Agent"
ufw allow 10051/tcp comment "Zabbix Server"
ufw --force enable
success "Firewall configured"

# =============================================================================
# 13. FINAL VERIFICATION
# =============================================================================
log "Verifying installation..."

# Check services
for service in zabbix-server zabbix-agent apache2 mariadb; do
    if systemctl is-active --quiet $service; then
        success "$service: ACTIVE"
    else
        error "$service: FAILED"
    fi
done

# Test DB connection
if mysql -u $DB_USER -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
    success "Database connection: OK"
else
    error "Database connection: FAILED"
fi

# Get IP
PI_IP=$(hostname -I | awk '{print $1}')
success "Zabbix Web Interface: http://$PI_IP/zabbix"

# =============================================================================
# 14. FINAL SUMMARY
# =============================================================================
cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                            INSTALLATION COMPLETE!                           ║
╚══════════════════════════════════════════════════════════════════════════════╝

${GREEN}✓${NC} Zabbix $ZABBIX_VERSION successfully installed on Debian 13.1
${GREEN}✓${NC} MariaDB database configured
${GREEN}✓${NC} All PHP dependencies installed
${GREEN}✓${NC} Apache2 web server configured
${GREEN}✓${NC} Firewall rules applied

${BLUE}WEB ACCESS:${NC}
┌─────────────────────────────────────┐
│ URL:          http://$PI_IP/zabbix  │
│ Username:     Admin                 │
│ Password:     zabbix                │
└─────────────────────────────────────┘

${YELLOW}IMPORTANT:${NC}
1. CHANGE DEFAULT PASSWORD IMMEDIATELY after first login!
2. Update DB_PASS in script variables for production use
3. Configure email alerts in Zabbix UI
4. Add hosts for monitoring

${BLUE}LOG FILE:${NC} $LOG_FILE
${BLUE}CONFIG FILES:${NC}
/etc/zabbix/zabbix_server.conf
/etc/zabbix/apache.conf

EOF

success "Installation completed successfully!"
