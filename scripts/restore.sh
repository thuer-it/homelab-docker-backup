#!/usr/bin/env bash
# =============================================================================
# restore.sh — Selektive Wiederherstellung
#
# Verwendung:
#   restore.sh list   <backup-dir>               # zeigt Inhalt
#   restore.sh volume <backup-dir> <volume-name> # stellt Volume wieder her
#   restore.sh db     <backup-dir> <dump-file>   # importiert DB-Dump
#   restore.sh all    <backup-dir>               # alles wiederherstellen
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/modules/lib.sh"

CMD="${1:-}"
BACKUP_DIR="${2:-}"

usage() {
  cat <<EOF
Verwendung:
  $(basename "$0") list   <backup-dir>
  $(basename "$0") volume <backup-dir> <volume-name>
  $(basename "$0") db     <backup-dir> <dump-datei>
  $(basename "$0") all    <backup-dir>
EOF
  exit 1
}

[[ -z "${CMD}" || -z "${BACKUP_DIR}" ]] && usage
[[ ! -d "${BACKUP_DIR}" ]] && die "Verzeichnis nicht gefunden: ${BACKUP_DIR}"

# ── list ──────────────────────────────────────────────────────────────────────
cmd_list() {
  log "Inhalt von: ${BACKUP_DIR}"
  echo ""
  echo "── DB-Dumps ──────────────────────────────"
  find "${BACKUP_DIR}/db" -name "*.sql.gz" 2>/dev/null \
    | while read -r f; do echo "  $(basename "${f}") ($(du -sh "${f}" | cut -f1))"; done \
    || echo "  (keine)"

  echo ""
  echo "── Volumes ───────────────────────────────"
  find "${BACKUP_DIR}/volumes" -name "*.tar.gz" 2>/dev/null \
    | while read -r f; do echo "  $(basename "${f}") ($(du -sh "${f}" | cut -f1))"; done \
    || echo "  (keine)"

  echo ""
  echo "── Bind-Mounts ───────────────────────────"
  find "${BACKUP_DIR}/bindmounts" -name "*.tar.gz" 2>/dev/null \
    | while read -r f; do echo "  $(basename "${f}") ($(du -sh "${f}" | cut -f1))"; done \
    || echo "  (keine)"

  echo ""
  echo "── Dockhand ──────────────────────────────"
  ls "${BACKUP_DIR}/dockhand/" 2>/dev/null || echo "  (keine)"
}

# ── volume ────────────────────────────────────────────────────────────────────
cmd_volume() {
  local vol_name="${3:-}"
  [[ -z "${vol_name}" ]] && usage

  local archive="${BACKUP_DIR}/volumes/${vol_name}.tar.gz"
  [[ ! -f "${archive}" ]] && die "Archiv nicht gefunden: ${archive}"

  if docker volume inspect "${vol_name}" &>/dev/null; then
    read -rp "Volume '${vol_name}' existiert bereits. Überschreiben? [y/N] " confirm
    [[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && { log "Abgebrochen."; exit 0; }
    docker volume rm "${vol_name}"
  fi

  docker volume create "${vol_name}"
  log "Stelle Volume '${vol_name}' wieder her…"

  docker run --rm \
    -v "${vol_name}:/data" \
    -v "$(realpath "${archive}"):/backup.tar.gz:ro" \
    alpine \
    sh -c "tar -xzf /backup.tar.gz -C /data"

  ok "Volume '${vol_name}' wiederhergestellt"
}

# ── db ────────────────────────────────────────────────────────────────────────
cmd_db() {
  local dump_file="${3:-}"
  [[ -z "${dump_file}" ]] && usage

  # Relativer Pfad → aus backup-dir
  [[ "${dump_file}" != /* ]] && dump_file="${BACKUP_DIR}/db/${dump_file}"
  [[ ! -f "${dump_file}" ]] && die "Dump nicht gefunden: ${dump_file}"

  # DB-Typ aus Dateiname ableiten oder fragen
  local db_type=""
  if [[ "${dump_file}" =~ postgres|pgvector|immich|netbox ]]; then
    db_type="postgres"
  elif [[ "${dump_file}" =~ mysql|mariadb|zabbix|snipeit|cypht|erpnext ]]; then
    db_type="mysql"
  else
    read -rp "DB-Typ? [postgres/mysql]: " db_type
  fi

  read -rp "Ziel-Container: " target_container

  case "${db_type}" in
    postgres)
      log "Importiere PostgreSQL-Dump in '${target_container}'…"
      local pg_user
      pg_user=$(docker exec "${target_container}" printenv POSTGRES_USER 2>/dev/null || echo "postgres")
      zcat "${dump_file}" | docker exec -i "${target_container}" psql -U "${pg_user}"
      ok "PostgreSQL-Dump importiert"
      ;;
    mysql)
      log "Importiere MySQL/MariaDB-Dump in '${target_container}'…"
      local root_pass
      root_pass=$(docker exec "${target_container}" printenv MARIADB_ROOT_PASSWORD 2>/dev/null \
        || docker exec "${target_container}" printenv MYSQL_ROOT_PASSWORD 2>/dev/null)
      zcat "${dump_file}" | docker exec -i "${target_container}" \
        mysql -u root -p"${root_pass}"
      ok "MySQL-Dump importiert"
      ;;
    *)
      die "Unbekannter DB-Typ: ${db_type}"
      ;;
  esac
}

# ── all ───────────────────────────────────────────────────────────────────────
cmd_all() {
  warn "Vollständige Wiederherstellung aus: ${BACKUP_DIR}"
  read -rp "Wirklich ALLE Volumes wiederherstellen? [y/N] " confirm
  [[ "${confirm}" != "y" && "${confirm}" != "Y" ]] && { log "Abgebrochen."; exit 0; }

  find "${BACKUP_DIR}/volumes" -name "*.tar.gz" 2>/dev/null | while read -r archive; do
    local vol_name
    vol_name=$(basename "${archive}" .tar.gz)
    cmd_volume "${CMD}" "${BACKUP_DIR}" "${vol_name}" <<< "y"
  done
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${CMD}" in
  list)   cmd_list   ;;
  volume) cmd_volume "$@" ;;
  db)     cmd_db     "$@" ;;
  all)    cmd_all    ;;
  *)      usage ;;
esac
