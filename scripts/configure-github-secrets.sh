#!/usr/bin/env bash
# Настроить секреты GitHub Actions; включение DEPLOY_ENABLED отдельно.
# Usage: bash scripts/configure-github-secrets.sh SERVER_HOST DEPLOY_USER SSH_PRIVATE_KEY KNOWN_HOSTS_FILE
set -Eeuo pipefail
[[ $# -ge 4 ]] || { echo "Usage: $0 SERVER_HOST DEPLOY_USER SSH_PRIVATE_KEY KNOWN_HOSTS_FILE [owner/repo]" >&2; exit 2; }
DEPLOY_HOST="$1"
DEPLOY_USER="$2"
KEY_FILE="$3"
HOSTS_FILE="$4"
REPOSITORY="${5:-Folcramus/devops-taskboard-demo}"
command -v gh >/dev/null || { echo 'GitHub CLI is required (https://cli.github.com/)'; exit 2; }
gh auth status >/dev/null || { echo 'Run gh auth login'; exit 2; }
[[ -r "$KEY_FILE" && -s "$KEY_FILE" ]] || { echo 'SSH private key file missing' >&2; exit 2; }
[[ -r "$HOSTS_FILE" && -s "$HOSTS_FILE" ]] || { echo 'Verified known_hosts file missing' >&2; exit 2; }
if ! grep -qvE '^[[:space:]]*(#|$)' "$HOSTS_FILE"; then
  echo 'known_hosts is empty or invalid' >&2; exit 2
fi
gh repo view "$REPOSITORY" >/dev/null 2>&1 || { echo "No access to $REPOSITORY"; exit 2; }
printf '%s' "$DEPLOY_HOST" | gh secret set DEPLOY_HOST -R "$REPOSITORY"
printf '%s' "$DEPLOY_USER" | gh secret set DEPLOY_USER -R "$REPOSITORY"
gh secret set DEPLOY_SSH_KEY -R "$REPOSITORY" < "$KEY_FILE"
gh secret set DEPLOY_KNOWN_HOSTS -R "$REPOSITORY" < "$HOSTS_FILE"
echo 'Secrets saved; DEPLOY_ENABLED remains disabled.'
printf 'To enable after server preflight: gh variable set DEPLOY_ENABLED --body true -R %s\n' "$REPOSITORY"
