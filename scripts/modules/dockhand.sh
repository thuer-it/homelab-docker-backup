#!/usr/bin/env bash
# =============================================================================
# dockhand.sh — Dockhand Stack-Konfiguration exportieren
# Exportiert:
#   - Alle Compose-Files via Dockhand-API (alle Environments)
#   - Dockhand-Datenbank-Volume (für kompletten Rebuild)
# =============================================================================

backup_dockhand() {
  if [[ "${DOCKHAND_ENABLED:-false}" != "true" ]]; then
    return 0
  fi

  local dest_dir
  dest_dir="$(backup_dir dockhand)"
  mkdir -p "${dest_dir}/compose"

  log "dockhand: Starte Export von ${DOCKHAND_URL}…"

  # ── 1. Compose-Files via API ──────────────────────────────────────────────
  # Stacks sind environment-spezifisch: erst Environments laden, dann je ?env=ID
  local envs_json
  if ! envs_json=$(curl -sf \
      -H "Authorization: Bearer ${DOCKHAND_TOKEN}" \
      "${DOCKHAND_URL}/api/environments" 2>/dev/null); then
    err "dockhand: API nicht erreichbar (${DOCKHAND_URL})"
    return 1
  fi

  local env_ids env_names
  mapfile -t env_ids   < <(echo "${envs_json}" | jq -r '.[].id')
  mapfile -t env_names < <(echo "${envs_json}" | jq -r '.[].name')

  local total_stacks=0
  local errors=0

  for i in "${!env_ids[@]}"; do
    local env_id="${env_ids[$i]}"
    local env_name="${env_names[$i]}"

    local stacks_json
    stacks_json=$(curl -sf \
      -H "Authorization: Bearer ${DOCKHAND_TOKEN}" \
      "${DOCKHAND_URL}/api/stacks?env=${env_id}" 2>/dev/null) || continue

    local stack_names
    mapfile -t stack_names < <(echo "${stacks_json}" | jq -r '.[].name' 2>/dev/null)
    [[ ${#stack_names[@]} -eq 0 ]] && continue

    mkdir -p "${dest_dir}/compose/${env_name}"

    for stack_name in "${stack_names[@]}"; do
      local compose_file="${dest_dir}/compose/${env_name}/${stack_name}.yml"
      local compose_raw
      if compose_raw=$(curl -sf \
           -H "Authorization: Bearer ${DOCKHAND_TOKEN}" \
           "${DOCKHAND_URL}/api/stacks/${stack_name}/compose?env=${env_id}" \
           2>/dev/null); then
        # API gibt ggf. JSON {content:"..."} oder direkt YAML zurück
        if echo "${compose_raw}" | jq -e '.content' >/dev/null 2>&1; then
          echo "${compose_raw}" | jq -r '.content' > "${compose_file}"
        else
          echo "${compose_raw}" > "${compose_file}"
        fi
        log "dockhand: [${env_name}] Stack '${stack_name}' exportiert"
        (( total_stacks++ )) || true
      else
        warn "dockhand: [${env_name}] Stack '${stack_name}' — kein Compose-File"
        (( errors++ )) || true
      fi
    done
  done

  ok "dockhand: ${total_stacks} Stacks exportiert, ${errors} ohne Compose-File"

  # ── 2. Dockhand-Datenbank-Volume ──────────────────────────────────────────
  # Ermittle Volume-Namen des Dockhand-Containers automatisch
  local dockhand_container
  dockhand_container=$(docker ps --filter "ancestor=fnsys/dockhand" \
    --format '{{.Names}}' | head -1)

  if [[ -z "${dockhand_container}" ]]; then
    warn "dockhand: Container nicht gefunden — Volume-Backup übersprungen"
    return 0
  fi

  local vol_backup="${dest_dir}/dockhand-volume.tar.gz"
  log "dockhand: Volume-Backup (${dockhand_container})…"

  if docker run --rm \
       --volumes-from "${dockhand_container}" \
       -v "${dest_dir}:/backup" \
       alpine \
       tar -czf /backup/dockhand-volume.tar.gz /app/data 2>/dev/null; then
    ok "dockhand: Volume → $(human_size "${vol_backup}")"
  else
    err "dockhand: Volume-Backup fehlgeschlagen"
    return 1
  fi
}
