# Развертывание TaskBoard на Ubuntu

Инструкция рассчитана на **отдельную учебную виртуальную машину** с Ubuntu 24.04 или новее, с SSH-доступом и установленным Docker Engine + Compose v2. Не используйте рабочие серверы без предварительного согласования.

## 1. Установить Docker

Войдите по SSH под администратором и выполните:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker compose version
```

## 2. Пользователь и SSH

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy
sudo install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
```

Добавьте **публичный ключ**, созданный специально для деплоя, в `/home/deploy/.ssh/authorized_keys`, выставьте права 0600 и владельца `deploy`. На компьютере оператора создайте пару ключей через `ssh-keygen -t ed25519 -f ~/.ssh/taskboard_deploy -C "devops-taskboard-deploy"`. Приватный ключ сохраните только в GitHub Secrets. Проверяйте отпечаток сервера до добавления его в known_hosts.

Группа `docker` фактически даёт администраторские возможности. Используйте отдельную изолированную учебную VM и не добавляйте в эту группу недоверенных пользователей.

## 3. Каталог и конфигурация

```bash
sudo install -d -m 0750 -o deploy -g deploy /opt/devops-taskboard
sudo -u deploy bash -c 'umask 077; cd /opt/devops-taskboard; printf "DB_USER=taskboard\nDB_NAME=taskboard\nHTTP_BIND=127.0.0.1\nHTTP_PORT=8080\n" > .env'
sudo -u deploy bash -c 'printf "DB_PASSWORD=%s\n" "$(openssl rand -hex 24)" >> /opt/devops-taskboard/.env'
```

Проверить наличие пароля без его вывода: `sudo -u deploy grep -q '^DB_PASSWORD=' /opt/devops-taskboard/.env && echo OK`.

## 4. Secrets в GitHub

В репозитории: Settings → Secrets and variables → Actions → New repository secret.

| Secret | Описание |
| --- | --- |
| `DEPLOY_HOST` | IP-адрес либо DNS сервера |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | содержимое **приватного** SSH-ключа |
| `DEPLOY_KNOWN_HOSTS` | запись known_hosts с проверенным host key |

Можно выполнить `bash scripts/configure-github-secrets.sh SERVER_IP deploy ~/.ssh/taskboard_deploy ~/.ssh/known_hosts` на своём компьютере, если установлен GitHub CLI.

Серверу требуется доступ к `ghcr.io/folcramus/devops-taskboard-demo`. Для приватного пакета настройте `docker login ghcr.io` от пользователя deploy с правом read:packages; для публичного пакета авторизация не требуется.

## 5. Включение CD

После появления workflow в GitHub и проверки всех секретов выполните локально:

```bash
gh variable set DEPLOY_ENABLED --body true -R Folcramus/devops-taskboard-demo
git commit --allow-empty -m "ci: trigger deployment"
git push origin main
```

Workflow загрузит `compose.prod.yaml`, Nginx-конфигурацию и скрипты, выполнит `deploy.sh`, дождётся `/readyz` и при сбое попробует восстановить предыдущий релиз.

Для доступа к сервису из браузера без публичного домена используйте туннель:
```bash
ssh -L 18080:127.0.0.1:8080 deploy@SERVER_IP
```
Откройте `http://127.0.0.1:18080`.

## 6. Диагностика и откат

На сервере:
```bash
cd /opt/devops-taskboard
bash scripts/server-preflight.sh
docker compose --env-file .env --env-file .release.env -f compose.prod.yaml ps
docker compose --env-file .env --env-file .release.env -f compose.prod.yaml logs -f
curl -fsS http://127.0.0.1:8080/readyz
bash scripts/rollback.sh
```

Откат возможен после минимум двух успешных релизов. PostgreSQL volume не удаляется при обновлении образов. Внешний доступ без авторизации не рекомендуется.
