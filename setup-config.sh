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

# 4. Korrekte Default-Konfiguration erstellen
echo -e "${GREEN}Erstelle MaxScale Konfiguration...${NC}"
cat > $CONFIG_FILE << 'EOF'
# MaxScale Konfiguration für 2 Server
# Host-Pfad: /opt/maxscale_config/maxscale.cnf
# Container-Pfad: /etc/maxscale.cnf

[maxscale]
# Basis-Einstellungen
threads=auto
log_info=true
log_warning=true
log_notice=false

# Admin Interface
admin_host=0.0.0.0
admin_port=8989
admin_secure_gui=false

# ===============================================
# Backend MariaDB/MySQL Server (2 Server Setup)
# ===============================================

# Master Server
# TODO: IP des Master-Servers anpassen falls nötig
[server1]
type=server
address=10.13.3.1
port=3306
protocol=MariaDBBackend
persistpoolmax=10
persistmaxtime=3600s

# Slave Server
# TODO: IP des Slave-Servers anpassen falls nötig
[server2]
type=server
address=10.13.3.2
port=3306
protocol=MariaDBBackend
persistpoolmax=10
persistmaxtime=3600s

# ===============================================
# Monitor für Health Checks und Failover
# ===============================================
[MariaDB-Monitor]
type=monitor
module=mariadbmon
servers=server1,server2
# TODO: Monitor-Benutzer und Passwort anpassen
user=maxscale_monitor
password=monitor_password
monitor_interval=2000ms
backend_connect_timeout=3s
backend_write_timeout=2s
backend_read_timeout=1s
backend_connect_attempts=1

# Failover-Einstellungen
auto_failover=true
auto_rejoin=true
failcount=5
assume_unique_hostnames=false

# ===============================================
# Services (Router)
# ===============================================

# Read/Write-Splitting Service
[Read-Write-Service]
type=service
router=readwritesplit
servers=server1,server2
# TODO: Router-Benutzer und Passwort anpassen
user=maxscale_user
password=router_password
max_slave_connections=100
slave_selection_criteria=ADAPTIVE_ROUTING
master_reconnection=true
master_failure_mode=error_on_write
transaction_replay=true
delayed_retry=true
connection_keepalive=300s
max_connections=1000

# Read-Only Service (nur Slave)
[Read-Only-Service]
type=service
router=readconnroute
servers=server2
# TODO: Router-Benutzer und Passwort anpassen
user=maxscale_user
password=router_password
router_options=slave
max_connections=1000
connection_timeout=10s

# ===============================================
# Listener (Ports)
# ===============================================

# Read/Write Port
[Read-Write-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=4006
address=0.0.0.0

# Read-Only Port
[Read-Only-Listener]
type=listener
service=Read-Only-Service
protocol=MariaDBClient
port=4008
address=0.0.0.0

# MySQL-kompatibler Port
[MySQL-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=3306
address=0.0.0.0
EOF

# 5. Berechtigungen setzen
echo -e "${GREEN}Setze Berechtigungen...${NC}"
chmod 644 $CONFIG_FILE
chown 999:999 $CONFIG_FILE

# 6. SQL-Setup-Datei erstellen
SQL_FILE="$CONFIG_DIR/setup-users.sql"
echo -e "${GREEN}Erstelle SQL-Setup-Datei...${NC}"
cat > $SQL_FILE << 'EOF'
-- MaxScale Benutzer auf MariaDB/MySQL einrichten
-- Diese Befehle auf BEIDEN Datenbank-Servern ausführen!

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

# 7. Test-Script erstellen
TEST_SCRIPT="$CONFIG_DIR/test-maxscale.sh"
echo -e "${GREEN}Erstelle Test-Script...${NC}"
cat > $TEST_SCRIPT << 'EOF'
#!/bin/bash
# Test-Script für MaxScale

echo "MaxScale Status prüfen..."
docker exec maxscale maxctrl show maxscale

echo -e "\nServer Status:"
docker exec maxscale maxctrl list servers

echo -e "\nServices:"
docker exec maxscale maxctrl list services

echo -e "\nMonitors:"
docker exec maxscale maxctrl list monitors

echo -e "\nVerbindung testen (Port 4006):"
echo "mysql -h 10.13.3.2 -P 4006 -u maxscale_user -p"
EOF

chmod +x $TEST_SCRIPT

# 8. Abschluss
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup abgeschlossen!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Erstellte Dateien:${NC}"
echo "  • Config:      $CONFIG_FILE"
echo "  • SQL:         $SQL_FILE"
echo "  • Test-Script: $TEST_SCRIPT"
echo ""
echo -e "${YELLOW}2-Server Setup:${NC}"
echo "  • Server 1 (Master): 10.13.3.1"
echo "  • Server 2 (Slave):  10.13.3.2"
echo ""
echo -e "${YELLOW}TODO - Config anpassen:${NC}"
echo "  1. Datenbank-Benutzer und Passwörter"
echo "  2. Optional: Server-IPs falls anders"
echo ""
echo "  nano $CONFIG_FILE"
echo ""
echo -e "${YELLOW}SQL auf beiden Servern ausführen:${NC}"
echo "  mysql -u root -p < $SQL_FILE"
echo ""
echo -e "${YELLOW}Nach dem Start testen:${NC}"
echo "  $TEST_SCRIPT"
echo ""
