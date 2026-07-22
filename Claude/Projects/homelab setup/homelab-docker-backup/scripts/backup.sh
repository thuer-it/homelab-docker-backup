#!/usr/bin/env bash
# =============================================================================
# homelab-docker-backup — Hauptscript
#
# Verwendung: backup.sh [-c /path/to/backup.conf] [-n] [-v]
#   -c  Konfigurationsdatei (Standard: /etc/homelab-backup/backup.conf)
#   -n  Dry-run (keine Dateien schreiben)
#   -v  Verbose
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="/etc/homelab-backup/backup.conf"
DRY_RUN=false
VERBOSE=false

# ── CLI ───────────────────────────────────────────────────────────────────────
while getopts "c:nv" opt; do
  case "${opt}" in
    c) CONF_FILE="${OPTARG}" ;;
    n) DRY_RUN=true ;;
    v) VERBOSE=true ;;
    *) echo "Verwendung: $0 [-c config] [-n] [-v]" >&2; exit 1 ;;
  esac
done

# ── Konfiguration laden ───────────────────────────────────────────────────────
if [[ ! -f "${CONF_FILE}" ]]; then
  echo "FEHLER: Konfigurationsdatei nicht gefunden: ${CONF_FILE}" >&2
  echo "→ cp config/backup.conf.example /etc/homelab-backup/backup.conf" >&2
  exit 1
fi

# Array-Defaults VOR source setzen, damit config sie überschreiben kann.
# WICHTIG: Nicht ":= ()" verwenden — das setzt einen Scalar auf den String "()"
# anstatt ein leeres Array zu initialisieren.
declare -a DB_CONTAINERS=()
declare -a EXTRA_PATHS=()
declare -a EXCLUDE_VOLUMES=()
declare -a EXCLUDE_CONTAINERS=()

# shellcheck source=/dev/null
source "${CONF_FILE}"

# Pflichtfelder prüfen
: "${BACKUP_ROOT:?BACKUP_ROOT muss gesetzt sein}"
: "${RETENTION_DAYS:=14}"
: "${DB_RETENTION_DAYS:=30}"
: "${SERVER_NAME:=$(hostname)}"

export BACKUP_DATE
BACKUP_DATE=$(date +%Y-%m-%d_%H%M%S)
export SERVER_NAME BACKUP_ROOT RETENTION_DAYS DB_RETENTION_DAYS
export DOCKHAND_ENABLED DOCKHAND_URL DOCKHAND_TOKEN
export NOTIFY_CMD DRY_RUN VERBOSE
export LOG_FILE="${LOG_FILE:-/var/log/homelab-backup.log}"

# ── Module laden ──────────────────────────────────────────────────────────────
for module in lib db_postgres db_mysql volumes bindmounts dockhand rotate; do
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/modules/${module}.sh"
done

# ── Lock-File (verhindert parallele Läufe) ────────────────────────────────────
LOCK_FILE="/run/homelab-backup.lock"
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "Backup läuft bereits (Lock: ${LOCK_FILE})" >&2
  exit 1
fi
trap 'flock -u 9; rm -f "${LOCK_FILE}"' EXIT

# ── NFS-Mount prüfen ─────────────────────────────────────────────────────────
if [[ ! -d "${BACKUP_ROOT}" ]]; then
  die "Backup-Root '${BACKUP_ROOT}' nicht erreichbar — NFS gemountet?"
fi

# ── Start ────────────────────────────────────────────────────────────────────
log "════════════════════════════════════════"
log "Backup Start: ${SERVER_NAME} / ${BACKUP_DATE}"
log "Ziel: ${BACKUP_ROOT}/${SERVER_NAME}/${BACKUP_DATE}"
[[ "${DRY_RUN}" == "true" ]] && warn "DRY-RUN — keine Dateien werden geschrieben"

ERRORS=0

# ── 1. Auto-Discovery: DB-Container erkennen ─────────────────────────────────
# Ermittelt alle laufenden Container und klassifiziert sie nach Image-Name.
# Explizit konfigurierte Container (DB_CONTAINERS) haben Vorrang.
# Ausschluss via EXCLUDE_CONTAINERS.

declare -A discovered_postgres=()
declare -A discovered_mysql=()

while IFS='|' read -r name image; do
  [[ -z "${name}" ]] && continue

  # Ausgeschlossene Container überspringen
  local_skip=false
  for excl in "${EXCLUDE_CONTAINERS[@]+"${EXCLUDE_CONTAINERS[@]}"}"; do
    [[ "${name}" == "${excl}" ]] && local_skip=true && break
  done
  [[ "${local_skip}" == "true" ]] && continue

  # Klassifizierung nach Image-Name (case-insensitive)
  # Nur den eigentlichen Image-Namen prüfen (ohne Registry-Prefix und Tag),
  # damit Applikations-Images wie "zabbix/zabbix-server-mysql" NICHT matchen.
  # Beispiele: "mariadb:10.11" → "mariadb" ✓  |  "zabbix/zabbix-web-nginx-mysql:6" → "zabbix-web-nginx-mysql" ✗
  lower_image="${image,,}"
  image_name="${lower_image##*/}"   # Registry-Prefix entfernen (alles bis letztem /)
  image_name="${image_name%%:*}"    # Tag entfernen (alles ab erstem :)
  if [[ "${image_name}" =~ ^(postgres|pgvector|timescaledb|postgis) ]]; then
    discovered_postgres["${name}"]="${image}"
  elif [[ "${image_name}" =~ ^(mysql|mariadb|percona) ]]; then
    discovered_mysql["${name}"]="${image}"
  fi
done < <(docker ps --format '{{.Names}}|{{.Image}}' 2>/dev/null)

# Explizit konfigurierte Container eintragen (überschreiben auto-discovery)
for entry in "${DB_CONTAINERS[@]+"${DB_CONTAINERS[@]}"}"; do
  c_name="${entry%%:*}"
  c_type="${entry##*:}"
  case "${c_type}" in
    postgres) discovered_postgres["${c_name}"]="(config)" ;;
    mysql)    discovered_mysql["${c_name}"]="(config)" ;;
    *) warn "Unbekannter DB-Typ '${c_type}' für '${c_name}'" ;;
  esac
done

# ── 2. Datenbank-Dumps ────────────────────────────────────────────────────────
log "── Datenbank-Dumps ──"

for name in "${!discovered_postgres[@]}"; do
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "[dry-run] postgres dump: ${name}"
  else
    backup_postgres "${name}" || (( ERRORS++ )) || true
  fi
done

for name in "${!discovered_mysql[@]}"; do
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "[dry-run] mysql dump: ${name}"
  else
    backup_mysql "${name}" || (( ERRORS++ )) || true
  fi
done

# ── 3. Docker Volumes ─────────────────────────────────────────────────────────
log "── Docker Volumes ──"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "[dry-run] volume backup"
else
  backup_volumes || (( ERRORS++ )) || true
fi

# ── 4. Bind-Mounts & Extra-Pfade ─────────────────────────────────────────────
log "── Bind-Mounts ──"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "[dry-run] bindmount backup"
else
  backup_bindmounts || (( ERRORS++ )) || true
fi

# ── 5. Dockhand-Export ───────────────────────────────────────────────────────
log "── Dockhand ──"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "[dry-run] dockhand export (enabled=${DOCKHAND_ENABLED:-false})"
else
  backup_dockhand || (( ERRORS++ )) || true
fi

# ── 6. Rotation ───────────────────────────────────────────────────────────────
log "── Rotation ──"
if [[ "${DRY_RUN}" == "true" ]]; then
  log "[dry-run] rotation"
else
  rotate_backups || true
fi

# ── Zusammenfassung ───────────────────────────────────────────────────────────
log "════════════════════════════════════════"
if [[ ${ERRORS} -eq 0 ]]; then
  ok "Backup abgeschlossen — keine Fehler"
else
  err "Backup abgeschlossen mit ${ERRORS} Fehler(n)"
  notify "Backup ${SERVER_NAME} fehlgeschlagen: ${ERRORS} Fehler"
  exit 1
fi
