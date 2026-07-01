# homelab-docker-backup

[![ShellCheck](https://github.com/thuer-it/homelab-docker-backup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/thuer-it/homelab-docker-backup/actions/workflows/shellcheck.yml)

Schlanker, modularer Backup-Stack für Docker-Homelabs. Kein Framework, keine Abhängigkeiten außer `docker`, `jq`, `curl` und Standard-Linux-Tools.

## Features

- **Auto-Discovery** — PostgreSQL, MySQL/MariaDB-Container werden automatisch anhand des Image-Namens erkannt. Neue Container werden ohne Config-Änderung gesichert.
- **DB-konsistente Dumps** — `pg_dumpall` / `mysqldump` vor dem Volume-Backup (kein korrupter Zustand)
- **Named Docker Volumes** — alle benannten Volumes, anonyme Hex-IDs werden übersprungen
- **Bind-Mounts** — automatisch aus laufenden Containern ermittelt + konfigurierbare Extra-Pfade
- **Dockhand-Export** — Compose-Files via API + Volume-Backup (optional)
- **Rotation** — konfigurierbarer Aufbewahrungszeitraum, getrennt für DBs und Rest
- **Dry-run** — `-n` Flag zeigt was gesichert würde, ohne etwas zu schreiben
- **systemd Timer** — mit `RandomizedDelaySec` für Multi-Server-Setups
- **Keine Image-Backups** — Images kommen aus Registries, nicht aus dem Backup

## Voraussetzungen

- Docker
- `jq`, `curl`, `gzip`, `tar` (Standard auf Debian/Ubuntu)
- NFS-Mount des Backup-Ziels unter `/mnt/nas` (oder konfigurierbar)

## Installation

```bash
git clone https://github.com/thuer-it/homelab-docker-backup.git
cd homelab-docker-backup
sudo ./install.sh
```

Der Installer:
1. Kopiert Scripts nach `/opt/homelab-docker-backup/`
2. Legt Konfiguration in `/etc/homelab-backup/backup.conf` an
3. Installiert und aktiviert den systemd Timer (täglich 02:30)

## Konfiguration

```bash
nano /etc/homelab-backup/backup.conf
```

Mindest-Konfiguration:

```bash
BACKUP_ROOT="/mnt/nas"       # NFS-Mountpoint
SERVER_NAME="monitoring"     # Unterverzeichnis auf dem NAS
RETENTION_DAYS=14
DB_RETENTION_DAYS=30
```

### Auto-Discovery (Standard — keine Konfiguration nötig)

Container mit Images die `postgres`, `pgvector`, `timescaledb`, `mysql` oder `mariadb` enthalten, werden **automatisch** gesichert.

### Explizite DB-Container (optional, für Sonderfälle)

```bash
DB_CONTAINERS=(
  "my-custom-db:postgres"   # Erzwingt postgres-Dump für diesen Container
  "legacy-db:mysql"
)
```

### Container vom Backup ausschließen

```bash
EXCLUDE_CONTAINERS=(
  "test-db"
  "dev-postgres"
)
```

### Extra-Pfade (Bind-Mounts außerhalb /var/lib/docker)

```bash
EXTRA_PATHS=(
  "/opt/symcon"
  "/opt/zigbee2mqtt"
)
```

### Dockhand (nur auf dem Dockhand-Server)

```bash
DOCKHAND_ENABLED=true
DOCKHAND_URL="http://localhost:3011"
DOCKHAND_TOKEN="dein-api-token"   # Dockhand → Settings → Auth Tokens
```

## Verwendung

```bash
# Dry-run: zeigt was gesichert würde
backup.sh -n

# Normales Backup
backup.sh

# Andere Konfigurationsdatei
backup.sh -c /etc/homelab-backup/backup-smarthome.conf
```

## Backup-Struktur auf dem NAS

```
/mnt/nas/
└── <server-name>/
    └── 2026-06-30_023000/
        ├── db/
        │   ├── netbox-postgres-2026-06-30_023000.sql.gz
        │   └── zabbix-mysql-2026-06-30_023000.sql.gz
        ├── volumes/
        │   ├── netbox_data.tar.gz
        │   └── zabbix_mysql_data.tar.gz
        ├── bindmounts/
        │   ├── opt_symcon.tar.gz
        │   └── home_pi_scripts.tar.gz
        └── dockhand/
            ├── dockhand-volume.tar.gz
            └── compose/
                ├── netbox.yml
                └── zabbix.yml
```

## Wiederherstellung

```bash
# Inhalt eines Backups anzeigen
restore.sh list /mnt/nas/monitoring/2026-06-30_023000

# Einzelnes Volume wiederherstellen
restore.sh volume /mnt/nas/monitoring/2026-06-30_023000 netbox_data

# DB-Dump importieren
restore.sh db /mnt/nas/monitoring/2026-06-30_023000 netbox-postgres-2026-06-30_023000.sql.gz

# Alle Volumes wiederherstellen (mit Bestätigung)
restore.sh all /mnt/nas/monitoring/2026-06-30_023000
```

## Multi-Server

Auf jedem Server wird das Repo geklont und `install.sh` ausgeführt. Die Konfiguration unterscheidet sich nur in `SERVER_NAME` und den jeweiligen Container-Listen (bei explizit konfigurierten DBs). Durch Auto-Discovery läuft auf den meisten Servern ohne jegliche Änderung an `DB_CONTAINERS`.

```
/mnt/nas/
├── monitoring/
├── smarthome/
├── klhof-infoserv/
└── erpserv01/
```

## Logs

```bash
# Echtzeit
journalctl -u homelab-backup -f

# Datei
tail -f /var/log/homelab-backup.log

# Letzter Timer-Lauf
systemctl status homelab-backup.timer
```

## Lizenz

MIT
