#!/usr/bin/env bash
# Проверка готовности Ubuntu до включения CD.
set -Eeuo pipefail
fail=0
report() { printf '%-43s %s\n' "$1" "$2"; }
check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then report "$1" OK; else report "$1" MISSING; fail=1; fi
}
for c in docker curl flock; do check_cmd "$c"; done
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then report 'Docker daemon access' OK; else report 'Docker daemon access' DENIED; fail=1; fi
  if docker compose version >/dev/null 2>&1; then report 'Compose v2' OK; else report 'Compose v2' MISSING; fail=1; fi
fi
BASE=/opt/devops-taskboard
if [[ -d "$BASE" && -w "$BASE" ]]; then report "$BASE writable" OK; else report "$BASE writable" NO; fail=1; fi
if [[ -f "$BASE/.env" ]]; then
  report '.env exists' OK
  if grep -Eq '^DB_PASSWORD=[[:alnum:]]{20,}$' "$BASE/.env" && ! grep -q CHANGE_ME "$BASE/.env"; then
    report 'DB_PASSWORD present' OK
  else
    report 'DB_PASSWORD present' 'INVALID OR TOO SHORT'; fail=1
  fi
else
  report '.env exists' NO; fail=1
fi
if [[ -f "$BASE/.release.env" ]]; then
  report 'Successful deployment manifest' PRESENT
else
  report 'Successful deployment manifest' 'not yet (normal before first deploy)'
fi
if ((fail)); then
  echo 'Preflight FAILED. Fix the above items before enabling DEPLOY_ENABLED.' >&2
  exit 1
fi
echo 'Server preflight PASSED.'
