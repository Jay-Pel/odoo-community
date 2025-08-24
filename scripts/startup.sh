#!/bin/bash
# Odoo startup script for Cloud Run
# Handles custom addons sync and database initialization

set -e

echo "Starting Odoo startup process..."

# Environment variables with defaults
DB_HOST=${DB_HOST:-"localhost"}
DB_NAME=${DB_NAME:-"odoo"}
DB_USER=${DB_USER:-"odoo"}
DB_PASSWORD=${DB_PASSWORD:-""}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"admin"}
CUSTOM_ADDONS_REPO=${CUSTOM_ADDONS_REPO:-""}
CUSTOM_ADDONS_BRANCH=${CUSTOM_ADDONS_BRANCH:-"main"}
ADDONS_PATH=${ADDONS_PATH:-"/opt/odoo/addons,/mnt/extra-addons"}

# Function to wait for database
wait_for_db() {
    echo "Waiting for database to be ready..."
    while ! python3 -c "
import psycopg2
try:
    conn = psycopg2.connect(
        host='$DB_HOST',
        database='postgres',
        user='$DB_USER',
        password='$DB_PASSWORD'
    )
    conn.close()
    print('Database is ready')
except:
    exit(1)
" 2>/dev/null; do
        echo "Database not ready, waiting 5 seconds..."
        sleep 5
    done
}

# Function to create database if it doesn't exist
create_database() {
    echo "Checking if database '$DB_NAME' exists..."
    
    DB_EXISTS=$(python3 -c "
import psycopg2
try:
    conn = psycopg2.connect(
        host='$DB_HOST',
        database='postgres',
        user='$DB_USER',
        password='$DB_PASSWORD'
    )
    cur = conn.cursor()
    cur.execute(\"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\")
    exists = cur.fetchone() is not None
    conn.close()
    print('true' if exists else 'false')
except Exception as e:
    print('false')
    print(f'Error: {e}', file=sys.stderr)
")

    if [ "$DB_EXISTS" = "false" ]; then
        echo "Database '$DB_NAME' does not exist, creating it..."
        python3 -c "
import psycopg2
conn = psycopg2.connect(
    host='$DB_HOST',
    database='postgres',
    user='$DB_USER',
    password='$DB_PASSWORD'
)
conn.autocommit = True
cur = conn.cursor()
cur.execute(\"CREATE DATABASE $DB_NAME\")
conn.close()
print('Database created successfully')
"
    else
        echo "Database '$DB_NAME' already exists"
    fi
}

# Function to sync custom addons
sync_custom_addons() {
    if [ -n "$CUSTOM_ADDONS_REPO" ]; then
        echo "Syncing custom addons from $CUSTOM_ADDONS_REPO (branch: $CUSTOM_ADDONS_BRANCH)..."
        
        # Clean existing addons directory
        rm -rf /mnt/extra-addons/*
        
        # Clone the repository
        git clone --branch "$CUSTOM_ADDONS_BRANCH" --depth 1 "$CUSTOM_ADDONS_REPO" /tmp/custom-addons
        
        # Copy addons to the addons directory
        if [ -d "/tmp/custom-addons" ]; then
            cp -r /tmp/custom-addons/* /mnt/extra-addons/ 2>/dev/null || true
            rm -rf /tmp/custom-addons
            echo "Custom addons synced successfully"
        else
            echo "Warning: Custom addons repository is empty or invalid"
        fi
        
        # Set proper permissions
        chown -R odoo:odoo /mnt/extra-addons
    else
        echo "No custom addons repository specified"
    fi
}

# Function to update odoo configuration
update_odoo_config() {
    echo "Updating Odoo configuration..."
    
    # Create configuration file with environment variables
    cat > /etc/odoo/odoo.conf << EOF
[options]
; Database configuration
db_host = $DB_HOST
db_port = 5432
db_user = $DB_USER
db_password = $DB_PASSWORD
; Path configuration
addons_path = $ADDONS_PATH
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
; Server configuration
http_port = 8080
workers = 2
max_cron_threads = 1
; Security
list_db = False
admin_passwd = $ADMIN_PASSWORD
; Performance (optimized for Cloud Run)
limit_memory_hard = 2147483648
limit_memory_soft = 1717986918
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
; Logging
log_level = info
log_handler = :INFO
; Proxy mode (required for Cloud Run)
proxy_mode = True
; Without demo data
without_demo = True
EOF

    chown odoo:odoo /etc/odoo/odoo.conf
    chmod 640 /etc/odoo/odoo.conf
}

# Main execution
echo "=== Odoo Cloud Run Startup ==="

# Wait for database
wait_for_db

# Create database if needed
create_database

# Sync custom addons
sync_custom_addons

# Update configuration
update_odoo_config

# Check if this is a first-time setup
NEEDS_INIT=$(python3 -c "
import psycopg2
try:
    conn = psycopg2.connect(
        host='$DB_HOST',
        database='$DB_NAME',
        user='$DB_USER',
        password='$DB_PASSWORD'
    )
    cur = conn.cursor()
    cur.execute(\"SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module'\")
    exists = cur.fetchone() is not None
    conn.close()
    print('false' if exists else 'true')
except:
    print('true')
")

if [ "$NEEDS_INIT" = "true" ]; then
    echo "First-time setup detected, initializing database..."
    echo "Installing base modules..."
    python3 /opt/odoo/odoo-bin -c /etc/odoo/odoo.conf -d "$DB_NAME" --init=base --stop-after-init --without-demo=all
    echo "Database initialized successfully"
fi

echo "Starting Odoo server..."
exec python3 /opt/odoo/odoo-bin -c /etc/odoo/odoo.conf -d "$DB_NAME"
