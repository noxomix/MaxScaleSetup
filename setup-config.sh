#!/bin/bash
# setup-maxscale-config.sh

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfigurationsverzeichnis auf dem HOST
CONFIG_DIR="/opt/maxscale_config"
CONFIG_FILE="$CONFIG_DIR/maxscale.cnf"

echo -e "${GREEN}MaxScale Config Setup Script${NC}"
echo "================================"

# 1. Prüfen ob als root/sudo
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Dieses Script muss als root ausgeführt werden${NC}" 
   exit 1
fi

# 2. Config-Verzeichnis auf HOST erstellen
echo -e "${YELLOW}Erstelle Konfigurationsverzeichnis...${NC}"
mkdir -p $CONFIG_DIR

# 3. Prüfen ob Config bereits existiert
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Konfiguration existiert bereits unter $CONFIG_FILE${NC}"
    read -p "Überschreiben? (j/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        echo -e "${GREEN}Behalte existierende Konfiguration.${NC}"
        exit 0
    fi
fi

# 4. Default-Konfiguration erstellen
echo -e "${GREEN}Erstelle MaxScale Konfiguration...${NC}"
cat > $CONFIG_FILE << 'EOF'
# MaxScale Konfiguration
# Host-Pfad: /opt/maxscale_config/maxscale.cnf
# Container-Pfad: /etc/maxscale.cnf

[maxscale]
# Basis-Einstellungen
threads=auto
log_info=true
log_warning=true
log_notice=false
log_debug=false

# Admin Interface
admin_host=0.0.0.0
admin_port=8989
admin_secure_gui=false

# ===============================================
# Backend MariaDB/MySQL Server
# ===============================================

# Master Server
[server1]
type=server
address=10.13.3.10  # TODO: IP des Master-Servers anpassen
port=3306
protocol=MariaDBBackend

# Slave Server 1
[server2]
type=server
address=10.13.3.11  # TODO: IP des ersten Slave-Servers anpassen
port=3306
protocol=MariaDBBackend

# Slave Server 2
[server3]
type=server
address=10.13.3.12  # TODO: IP des zweiten Slave-Servers anpassen
port=3306
protocol=MariaDBBackend

# ===============================================
# Monitor für Health Checks und Failover
# ===============================================
[MariaDB-Monitor]
type=monitor
module=mariadbmon
servers=server1,server2,server3
user=maxscale_monitor     # TODO: Monitor-Benutzer anpassen
password=monitor_password  # TODO: Monitor-Passwort anpassen
monitor_interval=2000

# Failover-Einstellungen
auto_failover=true
auto_rejoin=true
failcount=3
failover_timeout=90
master_failure_timeout=30

# ===============================================
# Services (Router)
# ===============================================

# Read/Write-Splitting Service
[Read-Write-Service]
type=service
router=readwritesplit
servers=server1,server2,server3
user=maxscale_user        # TODO: Router-Benutzer anpassen
password=router_password   # TODO: Router-Passwort anpassen
max_slave_connections=100
slave_selection_criteria=ADAPTIVE_ROUTING
master_reconnection=true
master_failure_mode=fail_on_write
transaction_replay=true

# Read-Only Service (nur Slaves)
[Read-Only-Service]
type=service
router=readconnroute
servers=server2,server3
user=maxscale_user        # TODO: Router-Benutzer anpassen
password=router_password   # TODO: Router-Passwort anpassen
router_options=slave

# ===============================================
# Listener (Ports)
# ===============================================

# Read/Write Port
[Read-Write-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=4006

# Read-Only Port
[Read-Only-Listener]
type=listener
service=Read-Only-Service
protocol=MariaDBClient
port=4008

# MySQL-kompatibler Port
[MySQL-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=3306
EOF

# 5. Berechtigungen setzen
echo -e "${GREEN}Setze Berechtigungen...${NC}"
chmod 644 $CONFIG_FILE
# MaxScale Container läuft normalerweise als UID 999
chown 999:999 $CONFIG_FILE

# 6. SQL-Setup-Datei erstellen
SQL_FILE="$CONFIG_DIR/setup-users.sql"
echo -e "${GREEN}Erstelle SQL-Setup-Datei...${NC}"
cat > $SQL_FILE << 'EOF'
-- MaxScale Benutzer auf MariaDB/MySQL einrichten
-- Diese Befehle auf ALLEN Datenbank-Servern ausführen!

-- Monitor-Benutzer (für Health-Checks)
CREATE USER IF NOT EXISTS 'maxscale_monitor'@'%' IDENTIFIED BY 'monitor_password';
GRANT REPLICATION CLIENT, SHOW DATABASES ON *.* TO 'maxscale_monitor'@'%';
GRANT SELECT ON mysql.* TO 'maxscale_monitor'@'%';

-- Router-Benutzer (für normale Verbindungen)
CREATE USER IF NOT EXISTS 'maxscale_user'@'%' IDENTIFIED BY 'router_password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER ON *.* TO 'maxscale_user'@'%';

FLUSH PRIVILEGES;

-- Überprüfung
SELECT User, Host FROM mysql.user WHERE User LIKE 'maxscale%';
EOF

chmod 644 $SQL_FILE

# 7. Abschluss
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup abgeschlossen!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Erstelle Dateien:${NC}"
echo "  • Config: $CONFIG_FILE"
echo "  • SQL:    $SQL_FILE"
echo ""
echo -e "${YELLOW}TODO - Config anpassen:${NC}"
echo "  1. Server-IPs (server1, server2, server3)"
echo "  2. Datenbank-Benutzer und Passwörter"
echo ""
echo "  nano $CONFIG_FILE"
echo ""
echo -e "${YELLOW}SQL auf allen DB-Servern ausführen:${NC}"
echo "  mysql -u root -p < $SQL_FILE"
echo ""
