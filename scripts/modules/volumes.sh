#!/usr/bin/env bash
# =============================================================================
# volumes.sh — Named Docker Volumes sichern
# Nur benannte Volumes (keine anonymen Hex-IDs, keine ausgeschlossenen)
# =============================================================================

backup_volumes() {
  local dest_dir
  dest_dir="$(backup_dir volumes)"
  mkdir -p "${dest_dir}"

  # Alle benannten Volumes ermitteln (anonyme = 64-Zeichen-Hex ausschließen)
  local volumes
  mapfile -t volumes < <(
    docker volume ls --format '{{.Name}}' \
      | grep -vE '^[0-9a-f]{64}$'
  )

  if [[ ${#volumes[@]} -eq 0 ]]; then
    warn "volumes: Keine benannten Volumes gefunden"
    return 0
  fi

  local errors=0
  for vol in "${volumes[@]}"; do
    # Ausschluss-Liste prüfen
    local skip=false
    for excl in "${EXCLUDE_VOLUMES[@]:-}"; do
      [[ "${vol}" == "${excl}" ]] && skip=true && break
    done
    if [[ "${skip}" == "true" ]]; then
      log "volumes: '${vol}'— übersprungen (Ausschlussliste)"
      continue
    fi

    local mountpoint
    mountpoint=$(docker volume inspect --format '{{.Mountpoint}}' "${vol}" 2>/dev/null)
    if [[ -z "${mountpoint}" || ! -d "${mountpoint}" ]]; then
      warn "volumes: '${vol}' — Mountpoint nicht erreichbar, übersprungen"
      continue
    fi

    local outfile="${dest_dir}/${vol}.tar.gz"
    log "volumes: '${vol}'…"

    if tar -czf "${outfile}" -C "${mountpoint}" . 2>/dev/null; then
      ok "volumes: '${vol}' → $(human_size "${outfile}")"
    else
      err "volumes: '${vol}' fehlgeschlagen"
      rm -f "${outfile}"
      (( errors++ )) || true
    fi
  done

  [[ ${errors} -gt 0 ]] && return 1
  return 0
}
