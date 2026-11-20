# Настройка Ubuntu-сервера с Windows для мастер-класса

> Учебный проект: `Folcramus/devops-taskboard-demo`. Настройка рассчитана на **отдельную VM**. Не используйте производственный сервер, пока не проверили, какие сервисы на нём работают. Корневой пароль не нужно помещать в командную строку или GitHub.

## 1. Windows PowerShell

Откройте PowerShell **под вашим обычным пользователем**, не обязательно от администратора.

Проверьте OpenSSH:

```powershell
ssh -V
scp -V
```

`scp -V` на некоторых сборках выводит справку вместо версии — это нормально. Если `ssh` отсутствует, включите компонент Windows «Клиент OpenSSH».

Установите Git и GitHub CLI, если они отсутствуют:

```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e
```

Откройте новый PowerShell, выполните авторизацию и клонируйте проект:

```powershell
gh auth login
git clone https://github.com/Folcramus/devops-taskboard-demo.git
cd devops-taskboard-demo
```

## 2. Генерация отдельного SSH-ключа для GitHub Actions

```powershell
New-Item -ItemType Directory -Force "$HOME\.ssh" | Out-Null
ssh-keygen -t ed25519 -f "$HOME\.ssh\taskboard_deploy" -C "taskboard-github-actions"
```

На запрос passphrase нажмите Enter дважды (ключ без passphrase требуется для автоматизации). Если ключ уже существует, **не перезаписывайте его**, иначе потребуется обновить authorized_keys и GitHub Secret.

В результате получатся:

- `$HOME\.ssh\taskboard_deploy` — приватный ключ. **Никому не показывайте и не отправляйте**.
- `$HOME\.ssh\taskboard_deploy.pub` — публичный ключ, который можно устанавливать на сервер.

## 3. Проверка отпечатка сервера

До первого SSH-соединения сравните host fingerprint с отпечатком, полученным из панели провайдера либо через доверенную веб-консоль VNC/IPMI. Если совпадение не подтверждено, не принимайте новый ключ наугад.

## 4. Подготовка сервера одной командой из Windows

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\bootstrap-from-windows.ps1 -ServerIp SERVER_IP
```

Замените `SERVER_IP` реальным IP. Скрипт:

1. Передаёт **публичный** SSH-ключ через SCP (ввод пароля root происходит только в SSH-запросе).
2. Скачивает и выполняет `scripts/bootstrap-server.sh` от root.
3. Исправляет испорченный Docker apt source, устанавливает Docker Engine и Compose v2.
4. Создаёт пользователя `deploy`, добавляет его SSH-ключ и подготавливает `/opt/devops-taskboard/.env`.
5. Копирует production Compose и скрипты, запускает `server-preflight.sh`.

Это только подготовка сервера: веб-приложение будет развернуто **после** настройки CI/CD.

## 5. Доверенный known_hosts

После независимой сверки fingerprint получите публичный SSH host key:

```powershell
ssh-keyscan -t ed25519 SERVER_IP | Out-File -Encoding ascii "$HOME\.ssh\taskboard_known_hosts"
ssh-keygen -lf "$HOME\.ssh\taskboard_known_hosts"
```

Нельзя полагаться только на `ssh-keyscan`: он получает ключ из сети, но не подтверждает его подлинность.

## 6. GitHub Secrets

Запустите скрипт, который проверит SSH-доступ и preflight, затем безопасно передаст приватный SSH-ключ из файла в GitHub Secrets (не в репозиторий).

```powershell
.\scripts\configure-from-windows.ps1 -ServerIp SERVER_IP
```

Секреты `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` будут сохранены. **CD останется выключенным.**

## 7. Доступ сервера к образам GitHub Container Registry

В GitHub Packages найдите пакет `devops-taskboard-demo`. Для учебной VM можно открыть видимость пакета `Public`; для закрытого проекта следует настроить на сервере `docker login ghcr.io` с token scope `read:packages`.

После завершения workflow `publish` проверьте с Windows:

```powershell
$sha = (gh api repos/Folcramus/devops-taskboard-demo/commits/main --jq .sha).Trim()
ssh -i "$HOME\.ssh\taskboard_deploy" deploy@SERVER_IP "docker pull ghcr.io/folcramus/devops-taskboard-demo:$sha"
```

Если образ ещё собирается, дождитесь успешного `publish`. Если получили `unauthorized`, проверьте видимость пакета или серверный `docker login`.

## 8. Включение автоматического CD

Только после успешного скачивания образа сервером:

```powershell
gh variable set DEPLOY_ENABLED --body true -R Folcramus/devops-taskboard-demo
gh workflow run ci-cd.yml -R Folcramus/devops-taskboard-demo
gh run list -R Folcramus/devops-taskboard-demo --limit 5
```

Откройте вкладку GitHub Actions; должны успешно завершиться `tests`, `publish` и `deploy`.

## 9. Проверка и просмотр сайта с Windows

```powershell
ssh -i "$HOME\.ssh\taskboard_deploy" deploy@SERVER_IP "cd /opt/devops-taskboard && docker compose --env-file .env --env-file .release.env -f compose.prod.yaml ps && curl -fsS http://127.0.0.1:8080/readyz"
```

Для просмотра сайта без публичного доступа откройте отдельный PowerShell:

```powershell
ssh -i "$HOME\.ssh\taskboard_deploy" -L 18080:127.0.0.1:8080 deploy@SERVER_IP
```

В браузере Windows откройте `http://127.0.0.1:18080`.

## 10. После настройки

- **Смените пароль root**, который оказался в переписке, командой `passwd` в SSH-сеансе root. Не отключайте root-доступ, пока не проверите альтернативный администраторский вход.
- Не открывайте учебный TaskBoard в интернет без HTTPS и защиты, так как приложение не имеет авторизации.
- Для отката после двух успешных выпусков: `ssh -i "$HOME\.ssh\taskboard_deploy" deploy@SERVER_IP "cd /opt/devops-taskboard && bash scripts/rollback.sh"`.
- Для диагностики: `ssh -i "$HOME\.ssh\taskboard_deploy" deploy@SERVER_IP "cd /opt/devops-taskboard && docker compose --env-file .env --env-file .release.env -f compose.prod.yaml logs --tail=100"`.

Если SSH на порт 22 не отвечает, проверьте правила сети/фаервола в панели хостинг-провайдера и состояние sshd через консоль провайдера; не пытайтесь раскрывать root-пароль в чат или отправлять его в сторонние сервисы.
