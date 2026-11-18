#!/usr/bin/env bash
# Деплой immutable образа ghcr.io/OWNER/REPO:40-символьный-SHA
set -Eeuo pipefail
cd "$(dirname "$0")/.."
IMAGE="${1:?Usage: bash scripts/deploy.sh ghcr.io/owner/repo:40-character-commit-sha}"
[[ "$IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+:[a-f0-9]{40}$ ]] || {
  echo "Некорректное имя образа: $IMAGE" >&2
  exit 2
}
[[ -f .env ]] || { echo 'Сначала создайте .env на сервере' >&2; exit 2; }
command -v flock >/dev/null || { echo 'Установите flock (util-linux)' >&2; exit 2; }
command -v curl >/dev/null || { echo 'Установите curl' >&2; exit 2; }

exec 9>.deploy.lock
flock -x 9
PORT="$(sed -n 's/^HTTP_PORT=//p' .env | tail -n 1)"
PORT="${PORT:-8080}"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "Неверный HTTP_PORT: $PORT" >&2; exit 2; }
VERSION="${IMAGE##*:}"
VERSION="${VERSION:0:12}"
PENDING="$(mktemp .release.pending.XXXXXX)"
trap 'rm -f "$PENDING"' EXIT
printf 'APP_IMAGE=%s\nAPP_VERSION=%s\n' "$IMAGE" "$VERSION" > "$PENDING"
chmod 600 "$PENDING"
compose() { docker compose --env-file .env --env-file "$1" -f compose.prod.yaml "${@:2}"; }
ready() {
  for i in $(seq 1 30); do
    if curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/readyz" >/dev/null; then
      echo "HTTP readiness OK"
      return 0
    fi
    sleep 2
  done
  return 1
}

echo "[DEPLOY] Pull: $IMAGE"
compose "$PENDING" pull app
if compose "$PENDING" up -d --no-build --wait --wait-timeout 150 && ready; then
  if [[ -f .release.env ]]; then cp .release.env .previous.env; fi
  mv "$PENDING" .release.env
  chmod 600 .release.env
  echo "[DEPLOY] Готово: $IMAGE"
else
  echo '[DEPLOY] Ошибка релиза, пробую восстановить прежний образ...' >&2
  if [[ -f .release.env ]]; then
    if compose .release.env up -d --no-build --wait --wait-timeout 150 && ready; then
      echo '[DEPLOY] Предыдущая версия восстановлена' >&2
    else
      echo '[DEPLOY] Не удалось восстановить сервис — проверьте логи!' >&2
    fi
  else
    echo '[DEPLOY] Предыдущей версии пока нет; проверьте docker compose logs' >&2
  fi
  exit 1
fi
