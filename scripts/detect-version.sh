#!/usr/bin/env bash
# Find the newest Grok Bot Windows installer that actually exists.
#
# Cursor/xAI does not publish latest.yml or a directory listing for
#   https://downloads.cursor.com/grokbot/stable/win32-x64/<ver>/Grok_Bot_<ver>_Setup.exe
# so this script HEAD-probes a bounded set of semver candidates above VERSION.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
WIN32_TMPL="https://downloads.cursor.com/grokbot/stable/win32-x64/%s/Grok_Bot_%s_Setup.exe"

log() { printf '%s\n' "$*" >&2; }

read_base() {
  if [[ -f "${VERSION_FILE}" ]]; then
    tr -d '[:space:]' < "${VERSION_FILE}"
  else
    printf '0.20.0'
  fi
}

http_head_ok() {
  local url="$1"
  local code
  code="$(curl --head --fail --silent --location --max-time 12 --retry 2 \
    -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
  [[ "${code}" == "200" ]]
}

probe() {
  local ver="$1" url
  url="$(printf "${WIN32_TMPL}" "${ver}" "${ver}")"
  http_head_ok "${url}"
}

candidates_from() {
  local major minor patch
  IFS='.' read -r major minor patch <<< "$1"
  if ! [[ "${major}" =~ ^[0-9]+$ && "${minor}" =~ ^[0-9]+$ && "${patch}" =~ ^[0-9]+$ ]]; then
    log "error: VERSION '$1' is not x.y.z"
    exit 1
  fi
  local -a raw=()
  local i
  for i in $(seq 1 12); do raw+=("${major}.${minor}.$((patch + i))"); done
  for i in $(seq 1 12); do raw+=("${major}.$((minor + i)).0"); done
  for i in $(seq 1 6); do raw+=("${major}.$((minor + i)).1"); done
  raw+=("$((major + 1)).0.0")
  printf '%s\n' "${raw[@]}" | sort -u -V -r
}

emit() {
  local version="$1" is_new="$2"
  printf 'version=%s\n' "${version}"
  printf 'is_new=%s\n' "${is_new}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      printf 'version=%s\n' "${version}"
      printf 'is_new=%s\n' "${is_new}"
    } >> "${GITHUB_OUTPUT}"
  fi
}

main() {
  local base dispatch latest
  base="$(read_base)"
  dispatch="${1:-${INPUT_VERSION:-}}"

  if [[ -n "${dispatch}" ]]; then
    log "checking requested version ${dispatch}"
    if ! probe "${dispatch}"; then
      log "error: ${dispatch} is not published (win32 installer HTTP != 200)"
      exit 1
    fi
    if [[ "${dispatch}" == "${base}" ]]; then
      emit "${dispatch}" "false"
    else
      emit "${dispatch}" "true"
    fi
    printf '%s\n' "${dispatch}"
    return 0
  fi

  log "base version: ${base}"
  local -a hits=()
  local cand
  while IFS= read -r cand; do
    [[ -z "${cand}" ]] && continue
    if probe "${cand}"; then
      log "  hit  ${cand}"
      hits+=("${cand}")
    else
      log "  miss ${cand}"
    fi
  done < <(candidates_from "${base}")

  if [[ ${#hits[@]} -eq 0 ]]; then
    log "no newer installer than ${base}"
    emit "${base}" "false"
    printf '%s\n' "${base}"
    return 0
  fi

  latest="$(printf '%s\n' "${hits[@]}" | sort -V | tail -n 1)"
  if [[ "$(printf '%s\n' "${base}" "${latest}" | sort -V | tail -n 1)" == "${latest}" && "${latest}" != "${base}" ]]; then
    emit "${latest}" "true"
  else
    emit "${latest}" "false"
  fi
  printf '%s\n' "${latest}"
}

main "${1:-}"
