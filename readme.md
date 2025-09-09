Dieses Setup dient dazu MariaDB Proxy pro Host zu betrieben. Also auf jedem vServer wo unser Dienst
läuft, lassen wir auch MaxScale laufen. Das bedeutet aber auch das wir auf jedem host einmal die 
Config die unser script hier generiert linken. Und dann einmal den setup ausführen. 

Der Setup ist die config zu bearbeiten mit allen Mariadb servern (erlaubt 3 ohne Lizenzkosten).
Das Limit betrifft aber die DB Server nicht die MaxScale Instanzen an sich. 

Auch müssen wir alle MariaDB/Mysql server vorher einmal die richtigen user usw anlegen. 

# 1. Setup ausführen
sudo ./setup-maxscale-config.sh

# 2. Passwörter anpassen
sudo nano /opt/maxscale_config/maxscale.cnf
sudo nano /opt/maxscale_config/setup-users.sql

# 3. SQL auf BEIDEN DB-Servern ausführen
mysql -u root -p < /opt/maxscale_config/setup-users.sql

# 4. MaxScale starten
docker-compose up -d

# 5. Testen
/opt/maxscale_config/test-maxscale.sh
