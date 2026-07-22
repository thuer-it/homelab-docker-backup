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

  # mysqldump-Argumente: --events und --routines weglassen wenn keine Rechte vorhanden
  local dump_args=(
    --single-transaction
    --quick
    --skip-lock-tables
    --skip-events
    --triggers
  )

  # Welches Binary ist verfügbar? (MariaDB 11+ nutzt mariadb-dump)
  local dump_bin
  if docker exec "${container}" which mariadb-dump >/dev/null 2>&1; then
    dump_bin="mariadb-dump"
  else
    dump_bin="mysqldump"
  fi

  if [[ -n "${root_pass}" ]]; then
    # Root-Dump: alle Datenbanken
    local dump_err
    dump_err=$(mktemp)
    if docker exec "${container}" \
         "${dump_bin}" -u root -p"${root_pass}" \
           --all-databases "${dump_args[@]}" \
         2>"${dump_err}" \
       | gzip > "${outfile}"; then
      rm -f "${dump_err}"
      ok "mysql: ${container} (all-databases) → $(human_size "${outfile}")"
      return 0
    else
      warn "mysql: Root-Dump fehlgeschlagen ($(head -1 "${dump_err}"))"
      rm -f "${dump_err}" "${outfile}"
    fi
  fi

  # Fallback: einzelne Datenbank mit User-Credentials
  if [[ -z "${db_name}" ]]; then
    err "mysql: Datenbankname für '${container}' nicht ermittelbar (MYSQL_DATABASE / MARIADB_DATABASE setzen)"
    return 1
  fi

  local dump_err2
  dump_err2=$(mktemp)
  if docker exec "${container}" \
       "${dump_bin}" -u "${db_user}" -p"${db_pass}" \
         "${dump_args[@]}" "${db_name}" \
       2>"${dump_err2}" \
     | gzip > "${outfile}"; then
    rm -f "${dump_err2}"
    ok "mysql: ${container} (${db_name}) → $(human_size "${outfile}")"
  else
    err "mysql: Dump von '${container}' fehlgeschlagen: $(head -1 "${dump_err2}")"
    rm -f "${dump_err2}" "${outfile}"
    return 1
  fi
}
