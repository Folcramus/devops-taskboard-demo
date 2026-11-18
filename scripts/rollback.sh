#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
[[ -f .previous.env ]] || { echo 'Нет предыдущего успешного релиза'; exit 1; }
IMAGE="$(sed -n 's/^APP_IMAGE=//p' .previous.env)"
[[ -n "$IMAGE" ]] || { echo 'Нет APP_IMAGE в .previous.env'; exit 1; }
bash scripts/deploy.sh "$IMAGE"
