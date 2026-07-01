#!/usr/bin/env bash
# =============================================================================
# dockhand.sh — Dockhand Stack-Konfiguration exportieren
# Exportiert:
#   - Alle Compose-Files via Dockhand-API
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
  local stacks_json
  if ! stacks_json=$(curl -sf \
      -H "Authorization: Bearer ${DOCKHAND_TOKEN}" \
      "${DOCKHAND_URL}/api/stacks" 2>/dev/null); then
    err "dockhand: API nicht erreichbar (${DOCKHAND_URL})"
    return 1
  fi

  local stack_ids
  mapfile -t stack_ids < <(echo "${stacks_json}" | jq -r '.[].id' 2>/dev/null)

  if [[ ${#stack_ids[@]} -eq 0 ]]; then
    warn "dockhand: Keine Stacks gefunden"
  fi

  local errors=0
  for id in "${stack_ids[@]}"; do
    local stack_info
    stack_info=$(curl -sf \
      -H "Authorization: Bearer ${DOCKHAND_TOKEN}" \
      "${DOCKHAND_URL}/api/stacks/${id}" 2>/dev/null) || continue

    local name env_id
    name=$(echo "${stack_info}" | jq -r '.name // "stack-'"${id}"'"')
    env_id=$(echo "${stack_info}" | jq -r '.environmentId // empty')

    # Compose-File exportieren
    local compose_file="${dest_dir}/compose/${name}.yml"
    if curl -sf \
         -H "Authorization: Bearer ${DOCKHAND_TOKEN}" \
         "${DOCKHAND_URL}/api/stacks/${id}/compose?env=${env_id}" \
         -o "${compose_file}" 2>/dev/null; then
      log "dockhand: Stack '${name}' exportiert"
    else
      warn "dockhand: Stack '${name}'— kein Compose-File (discovered?)"
      (( errors++ )) || true
    fi
  done

  ok "dockhand: ${#stack_ids[@]} Stacks verarbeitet, ${errors} ohne Compose-File"

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
