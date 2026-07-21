#!/usr/bin/env bash
# =============================================================================
# db_postgres.sh — PostgreSQL / pgvector Dumps
# =============================================================================

backup_postgres() {
  local container="$1"
  local dest_dir
  dest_dir="$(backup_dir db)"
  mkdir -p "${dest_dir}"

  if ! container_running "${container}"; then
    warn "postgres: Container '${container}' läuft nicht — übersprungen"
    return 0
  fi

  local db_user
  db_user=$(container_env "${container}" POSTGRES_USER) \
    || db_user=$(container_env "${container}" PGUSER) \
    || db_user="postgres"

  local outfile="${dest_dir}/${container}-${BACKUP_DATE}.sql.gz"

  log "postgres: Dump ${container} (user=${db_user})…"

  # pg_dumpall sichert alle DBs inkl. Rollen und Erweiterungen (pgvector, etc.)
  if docker exec -t "${container}" \
       pg_dumpall -U "${db_user}" --clean --if-exists \
     | gzip > "${outfile}"; then
    ok "postgres: ${container} → $(human_size "${outfile}")"
  else
    err "postgres: Dump von '${container}' fehlgeschlagen"
    rm -f "${outfile}"
    return 1
  fi
}
