#!/usr/bin/env bash
# =============================================================================
# install.sh — Einmaliges Setup auf einem Server
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/homelab-docker-backup"
CONF_DIR="/etc/homelab-backup"

echo "=== homelab-docker-backup Installer ==="

# Root?
if [[ "${EUID}" -ne 0 ]]; then
  echo "Bitte als root ausführen (sudo ./install.sh)" >&2
  exit 1
fi

# Abhängigkeiten
echo "→ Prüfe Abhängigkeiten…"
missing=()
for cmd in docker jq curl gzip tar; do
  command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Fehlende Pakete: ${missing[*]}"
  echo "Installation: apt install -y ${missing[*]}"
  exit 1
fi

# Scripts kopieren (nur wenn nicht bereits am Zielort)
echo "→ Installiere nach ${INSTALL_DIR}…"
mkdir -p "${INSTALL_DIR}"
if [[ "$(realpath "${SCRIPT_DIR}")" != "$(realpath "${INSTALL_DIR}")" ]]; then
  cp -r scripts/ "${INSTALL_DIR}/"
else
  echo "  → Scripts bereits in ${INSTALL_DIR} — Copy übersprungen"
fi
chmod +x "${INSTALL_DIR}/scripts/backup.sh"
chmod +x "${INSTALL_DIR}/scripts/restore.sh"
chmod +x "${INSTALL_DIR}/scripts/modules/"*.sh

# Konfiguration
echo "→ Konfiguration in ${CONF_DIR}…"
mkdir -p "${CONF_DIR}"
if [[ ! -f "${CONF_DIR}/backup.conf" ]]; then
  cp config/backup.conf.example "${CONF_DIR}/backup.conf"
  echo ""
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║  WICHTIG: Konfiguration anpassen!                   ║"
  echo "  ║  nano ${CONF_DIR}/backup.conf        ║"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo ""
else
  echo "  → backup.conf existiert bereits — nicht überschrieben"
fi

# Log-Datei
touch /var/log/homelab-backup.log
chmod 640 /var/log/homelab-backup.log

# systemd
echo "→ systemd Timer installieren…"
cp systemd/homelab-backup.service /etc/systemd/system/
cp systemd/homelab-backup.timer   /etc/systemd/system/

# Service-Pfad aktualisieren
sed -i "s|/opt/homelab-docker-backup|${INSTALL_DIR}|g" \
  /etc/systemd/system/homelab-backup.service

systemctl daemon-reload
systemctl enable homelab-backup.timer
systemctl start  homelab-backup.timer

echo ""
echo "✓ Installation abgeschlossen"
echo ""
echo "Nächste Schritte:"
echo "  1. nano ${CONF_DIR}/backup.conf    # Konfiguration anpassen"
echo "  2. ${INSTALL_DIR}/scripts/backup.sh -n  # Dry-run testen"
echo "  3. ${INSTALL_DIR}/scripts/backup.sh     # Erstes Backup"
echo "  4. systemctl list-timers homelab-backup  # Timer prüfen"
echo ""
echo "Restore-Hilfe:"
echo "  ${INSTALL_DIR}/scripts/restore.sh list <backup-verzeichnis>"
