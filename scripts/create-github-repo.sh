#!/usr/bin/env bash
# Для участников мастер-класса: создание собственного репозитория.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
OWNER="${1:?Usage: bash scripts/create-github-repo.sh YOUR_USERNAME [repo-name]}"
REPO="${2:-devops-taskboard-demo}"
command -v gh >/dev/null || { echo 'Install GitHub CLI (gh)'; exit 2; }
gh auth status >/dev/null || { echo 'Run gh auth login'; exit 2; }
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then echo "Repo already exists"; exit 3; fi
if [[ ! -d .git ]]; then git init; git branch -M main; fi
git add .
if ! git diff --cached --quiet; then git commit -m 'feat: initial TaskBoard workshop'; fi
gh repo create "$OWNER/$REPO" --public --source=. --remote=origin --push
