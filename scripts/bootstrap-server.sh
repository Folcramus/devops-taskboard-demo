#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "Run as root: bash scripts/bootstrap-server.sh /root/taskboard_deploy.pub" >&2
  exit 1
fi

PUBLIC_KEY_FILE="${1:-}"
[[ -r "$PUBLIC_KEY_FILE" ]] || { echo "Public SSH key file is missing: $PUBLIC_KEY_FILE" >&2; exit 2; }
PUBLIC_KEY="$(head -n 1 "$PUBLIC_KEY_FILE" | tr -d '\r')"
[[ "$PUBLIC_KEY" =~ ^ssh-ed25519[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo "Expected an ssh-ed25519 public key" >&2
  exit 2
}

source /etc/os-release
case "${ID:-}" in
  ubuntu)
    DOCKER_OS=ubuntu
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    ;;
  debian)
    DOCKER_OS=debian
    CODENAME="${VERSION_CODENAME:-}"
    ;;
  *)
    echo "Unsupported OS: ${ID:-unknown}. Use Ubuntu or Debian." >&2
    exit 2
    ;;
esac
[[ -n "$CODENAME" ]] || { echo "OS codename not found" >&2; exit 2; }

if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
  if grep -q 'download.docker.com' /etc/apt/sources.list.d/docker.list; then
    mv /etc/apt/sources.list.d/docker.list "/root/docker.list.backup.$(date +%Y%m%d%H%M%S)"
  fi
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git openssl util-linux
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$DOCKER_OS/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$DOCKER_OS
Suites: $CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

if ! id deploy >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash deploy
fi
usermod -aG docker deploy
install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
touch /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
if ! grep -Fqx "$PUBLIC_KEY" /home/deploy/.ssh/authorized_keys; then
  printf '%s\n' "$PUBLIC_KEY" >> /home/deploy/.ssh/authorized_keys
fi

BASE=/opt/devops-taskboard
install -d -m 0750 -o deploy -g deploy "$BASE"
install -d -m 0750 -o deploy -g deploy "$BASE/scripts" "$BASE/nginx"
if [[ ! -e "$BASE/.env" ]]; then
  DB_PASSWORD="$(openssl rand -hex 24)"
  (umask 077; cat > "$BASE/.env" <<EOF
DB_USER=taskboard
DB_NAME=taskboard
DB_PASSWORD=$DB_PASSWORD
HTTP_BIND=127.0.0.1
HTTP_PORT=8080
EOF
  )
fi
chown deploy:deploy "$BASE/.env"
chmod 600 "$BASE/.env"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
git clone --quiet --depth 1 https://github.com/Folcramus/devops-taskboard-demo.git "$STAGING/project"
install -m 0644 -o deploy -g deploy "$STAGING/project/compose.prod.yaml" "$BASE/compose.prod.yaml"
install -m 0644 -o deploy -g deploy "$STAGING/project/nginx/default.conf" "$BASE/nginx/default.conf"
for filename in deploy.sh rollback.sh server-preflight.sh; do
  install -m 0755 -o deploy -g deploy "$STAGING/project/scripts/$filename" "$BASE/scripts/$filename"
done

echo
echo "========== SERVER CHECK =========="
runuser -u deploy -- bash -c "cd '$BASE' && bash scripts/server-preflight.sh"
echo
echo "Server prepared for CI/CD."
echo "Deployment is intentionally NOT enabled before GitHub secrets and GHCR access are checked."
echo "SSH test from Windows: ssh -i \\$HOME\\.ssh\\taskboard_deploy deploy@SERVER_IP"
echo "Remember to rotate the exposed root password after verifying access."
