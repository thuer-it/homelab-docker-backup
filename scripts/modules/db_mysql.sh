#!/usr/bin/env bash
# =============================================================================
# db_mysql.sh — MySQL / MariaDB Dumps
# =============================================================================

backup_mysql() {
  local container="$1"
  local dest_dir
  dest_dir="$(backup_dir db)"
  mkdir -p "${dest_dir}"

  if ! container_running "${container}"; then
    warn "mysql: Container '${container}' läuft nicht — übersprungen"
    return 0
  fi

  # Passwort: root bevorzugen, dann user-Passwort
  local root_pass
  root_pass=$(container_env "${container}" MARIADB_ROOT_PASSWORD) \
    || root_pass=$(container_env "${container}" MYSQL_ROOT_PASSWORD)

  local db_user db_pass db_name
  db_user=$(container_env "${container}" MARIADB_USER) \
    || db_user=$(container_env "${container}" MYSQL_USER) \
    || db_user="root"
  db_pass=$(container_env "${container}" MARIADB_PASSWORD) \
    || db_pass=$(container_env "${container}" MYSQL_PASSWORD) \
    || db_pass=""
  db_name=$(container_env "${container}" MARIADB_DATABASE) \
    || db_name=$(container_env "${container}" MYSQL_DATABASE) \
    || db_name=""

  local outfile="${dest_dir}/${container}-${BACKUP_DATE}.sql.gz"
  log "mysql: Dump ${container}…"

  local dump_args=(
    --single-transaction
    --quick
    --skip-lock-tables
    --routines
    --triggers
    --events
  )

  if [[ -n "${root_pass}" ]]; then
    # Root-Dump: alle Datenbanken
    if docker exec "${container}" \
         mysqldump -u root -p"${root_pass}" \
           --all-databases "${dump_args[@]}" \
       | gzip > "${outfile}"; then
      ok "mysql: ${container} (all-databases) → $(human_size "${outfile}")"
      return 0
    fi
  fi

  # Fallback: einzelne Datenbank mit User-Credentials
  if [[ -z "${db_name}" ]]; then
    err "mysql: Datenbankname für '${container}' nicht ermittelbar"
    return 1
  fi

  if docker exec "${container}" \
       mysqldump -u "${db_user}" -p"${db_pass}" \
         "${dump_args[@]}" "${db_name}" \
     | gzip > "${outfile}"; then
    ok "mysql: ${container} (${db_name}) → $(human_size "${outfile}")"
  else
    err "mysql: Dump von '${container}' fehlgeschlagen"
    rm -f "${outfile}"
    return 1
  fi
}
