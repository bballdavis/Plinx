#!/bin/bash

# Shared loader for the repository's ignored, flat test credential file.
# Callers may report configured/absent state, but must never print values.

plinx_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

plinx_strip_yaml_quotes() {
  local value="$1"
  if [[ ${#value} -ge 2 && "$value" == \"*\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ ${#value} -ge 2 && "$value" == \'*\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

load_plinx_test_credentials() {
  local credentials_file="$1"
  [[ -f "$credentials_file" ]] || return 1

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    local line key value
    line="$(plinx_trim "$raw_line")"
    [[ -z "$line" || "$line" == \#* || "$line" != *:* ]] && continue

    key="$(plinx_trim "${line%%:*}")"
    value="$(plinx_trim "${line#*:}")"
    value="$(plinx_strip_yaml_quotes "$value")"

    case "$key" in
      PLINX_PLEX_SERVER_URL|PLINX_PLEX_TOKEN)
        export "$key=$value"
        ;;
    esac
  done < "$credentials_file"

  [[ -n "${PLINX_PLEX_SERVER_URL:-}" && -n "${PLINX_PLEX_TOKEN:-}" ]]
}
