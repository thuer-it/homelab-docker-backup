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
