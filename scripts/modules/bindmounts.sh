#!/usr/bin/env bash
# =============================================================================
# bindmounts.sh — Bind-Mounts und Extra-Pfade sichern
# Sichert:
#   1. Alle Bind-Mounts laufender Container (außer Systemspfade)
#   2. EXTRA_PATHS aus der Konfiguration
# =============================================================================

# Systemspfade die nie gesichert werden
readonly BINDMOUNT_SKIP_PREFIXES=(
  /proc /sys /dev /run /tmp
  /var/run /var/lib/docker
  /etc/localtime /etc/timezone /etc/hosts /etc/resolv.conf /etc/hostname
)

_should_skip() {
  local path="$1"
  for prefix in "${BINDMOUNT_SKIP_PREFIXES[@]}"; do
    [[ "${path}" == "${prefix}" || "${path}" == "${prefix}/"* ]] && return 0
  done
  return 1
}

backup_bindmounts() {
  local dest_dir
  dest_dir="$(backup_dir bindmounts)"
  mkdir -p "${dest_dir}"

  # Bind-Mounts aus laufenden Containern ermitteln
  local auto_paths=()
  while IFS= read -r src; do
    [[ -z "${src}" ]] && continue
    _should_skip "${src}" && continue
    auto_paths+=("${src}")
  done < <(
    docker inspect $(docker ps -q) \
      --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
      2>/dev/null | sort -u
  )

  # Zusammenführen mit EXTRA_PATHS (Duplikate entfernen)
  local all_paths=()
  declare -A seen=()
  for p in "${auto_paths[@]}" "${EXTRA_PATHS[@]:-}"; do
    [[ -z "${p}" || -n "${seen[$p]:-}" ]] && continue
    seen["${p}"]=1
    all_paths+=("${p}")
  done

  if [[ ${#all_paths[@]} -eq 0 ]]; then
    log "bindmounts: Keine Pfade gefunden"
    return 0
  fi

  local errors=0
  for src in "${all_paths[@]}"; do
    if [[ ! -e "${src}" ]]; then
      warn "bindmounts: '${src}' existiert nicht, übersprungen"
      continue
    fi

    # Pfad → sicherer Dateiname: /opt/symcon → opt_symcon.tar.gz
    local safe_name
    safe_name=$(echo "${src}" | sed 's|^/||; s|/|_|g')
    local outfile="${dest_dir}/${safe_name}.tar.gz"

    log "bindmounts: '${src}'…"
    if tar -czf "${outfile}" "${src}" 2>/dev/null; then
      ok "bindmounts: '${src}' → $(human_size "${outfile}")"
    else
      err "bindmounts: '${src}' fehlgeschlagen"
      rm -f "${outfile}"
      (( errors++ )) || true
    fi
  done

  [[ ${errors} -gt 0 ]] && return 1
  return 0
}
