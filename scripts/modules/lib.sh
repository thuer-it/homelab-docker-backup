#!/usr/bin/env bash
# =============================================================================
# lib.sh — Gemeinsame Hilfsfunktionen
# =============================================================================

# Farben (nur wenn Terminal)
if [[ -t 1 ]]; then
  C_RED='\033[0;31m'; C_GRN='\033[0;32m'; C_YLW='\033[0;33m'
  C_BLU='\033[0;34m'; C_RST='\033[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_RST=''
fi

LOG_FILE="${LOG_FILE:-/var/log/homelab-backup.log}"

log()  { local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
         echo -e "${C_BLU}[${ts}]${C_RST} $*" | tee -a "${LOG_FILE}"; }
ok()   { local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
         echo -e "${C_GRN}[${ts}] ✓${C_RST} $*" | tee -a "${LOG_FILE}"; }
warn() { local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
         echo -e "${C_YLW}[${ts}] ⚠${C_RST}  $*" | tee -a "${LOG_FILE}"; }
err()  { local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
         echo -e "${C_RED}[${ts}] ✗${C_RST} $*" | tee -a "${LOG_FILE}" >&2; }
die()  { err "$*"; notify "$*"; exit 1; }

# Benachrichtigung bei Fehler
notify() {
  [[ -z "${NOTIFY_CMD:-}" ]] && return 0
  eval "${NOTIFY_CMD}" "$1" || true
}

# Container existiert und läuft?
container_running() {
  docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null | grep -q "^true$"
}

# Env-Variable aus Container lesen
container_env() {
  docker exec "$1" printenv "$2" 2>/dev/null
}

# Backup-Verzeichnis für heute
backup_dir() {
  echo "${BACKUP_ROOT}/${SERVER_NAME}/${BACKUP_DATE}/$1"
}

# Dateigröße human-readable
human_size() {
  du -sh "$1" 2>/dev/null | cut -f1
}
