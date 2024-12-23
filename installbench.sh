#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[*] \$1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}[!] \$1${NC}"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        print_status "\$1 completed successfully"
    else
        print_error "\$1 failed"
        exit 1
    fi
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (sudo)"
   exit 1
fi

# Set timezone
print_status "Setting up timezone..."
dpkg-reconfigure tzdata
check_status "Timezone setup"

# Update and upgrade system
print_status "Updating system packages..."
apt-get update -y && apt-get upgrade -y
check_status "System update"

# Create new user
print_status "Creating new user for Frappe..."
read -p "Enter username for Frappe: " frappe_user
adduser $frappe_user
usermod -aG sudo $frappe_user
check_status "User creation"

# Install dependencies
print_status "Installing dependencies..."
apt-get install -y git python3-dev python3.10-dev python3-setuptools python3-pip python3-distutils \
    python3.10-venv software-properties-common mariadb-server mariadb-client redis-server \
    xvfb libfontconfig wkhtmltopdf libmysqlclient-dev curl
check_status "Dependencies installation"

# Configure MySQL
print_status "Securing MySQL installation..."
mysql_secure_installation

# Configure MySQL character set
print_status "Configuring MySQL character set..."
cat >> /etc/mysql/my.cnf << EOF

[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

# Restart MySQL
print_status "Restarting MySQL..."
service mysql restart
check_status "MySQL restart"

# Switch to frappe user for remaining installation
print_status "Switching to frappe user and continuing installation..."
su - $frappe_user << 'EOF'
# Install NVM
curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install Node.js
nvm install 22

# Install npm and yarn
sudo apt-get install -y npm
sudo npm install -g yarn

# Install bench
sudo pip3 install frappe-bench

# Initialize bench
bench init --frappe-branch version-15 frappe-bench
cd frappe-bench/

# Set permissions
sudo chmod -R o+rx /home/$USER/

# Create new site
read -p "Enter site name (example.com): " site_name
bench new-site $site_name

# Install apps
bench get-app payments
bench get-app --branch version-15 erpnext
bench get-app --branch version-15 hrms

# Install ERPNext on site
bench --site $site_name install-app erpnext

# Enable scheduler and disable maintenance mode
bench --site $site_name enable-scheduler
bench --site $site_name set-maintenance-mode off

# Setup production
sudo bench setup production $USER
bench setup nginx

# Restart supervisor
sudo supervisorctl restart all
sudo bench setup production $USER

# Configure firewall
sudo ufw allow 22,25,143,80,443,3306,3022,8000/tcp
sudo ufw enable
EOF

print_status "Installation completed successfully!"
print_status "You can now access your ERPNext instance at http://$site_name"
print_status "Please make sure to set up SSL certificates for production use"
