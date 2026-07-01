#!/usr/bin/env bash
# =============================================================================
# rotate.sh — Alte Backups löschen
# =============================================================================

rotate_backups() {
  local base="${BACKUP_ROOT}/${SERVER_NAME}"

  if [[ ! -d "${base}" ]]; then
    warn "rotate: Basis-Verzeichnis '${base}' nicht gefunden"
    return 0
  fi

  log "rotate: Aufräumen in '${base}'…"

  local deleted=0

  # DB-Dumps: eigene Aufbewahrungszeit
  while IFS= read -r f; do
    rm -f "${f}"
    (( deleted++ )) || true
  done < <(find "${base}" -path "*/db/*.sql.gz" -mtime +"${DB_RETENTION_DAYS}" 2>/dev/null)

  # Alles andere (volumes, bindmounts, dockhand): RETENTION_DAYS
  while IFS= read -r f; do
    rm -f "${f}"
    (( deleted++ )) || true
  done < <(find "${base}" \
    \( -path "*/volumes/*.tar.gz" \
       -o -path "*/bindmounts/*.tar.gz" \
       -o -path "*/dockhand/*.tar.gz" \) \
    -mtime +"${RETENTION_DAYS}" 2>/dev/null)

  # Leere Datumsverzeichnisse entfernen
  find "${base}" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true

  ok "rotate: ${deleted} Dateien gelöscht (DB: >${DB_RETENTION_DAYS}d, Rest: >${RETENTION_DAYS}d)"
}
