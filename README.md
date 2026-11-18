# DevOps TaskBoard — мастер-класс

Учебный проект: **Python / FastAPI + фронтенд HTML/CSS/JavaScript + PostgreSQL + Nginx + Docker Compose + pytest + GitHub Actions + GHCR + SSH-деплой + rollback**.

Проект предназначен для демонстрации полного пути от `git push` до работающего контейнерного приложения на Ubuntu. В интерфейсе можно добавлять задачи, задавать приоритет, отмечать выполнение и удалять задачи; номер версии выводится в верхней части TaskBoard.

> **Безопасность:** это учебное приложение **без логина и разграничения доступа**. По умолчанию Docker Compose публикует веб-интерфейс только на `127.0.0.1:8080`. Не открывайте его в интернет без HTTPS и авторизации.

## 1. Запуск на ноутбуке

Требуются Docker Engine и Compose v2.

```bash
git clone https://github.com/Folcramus/devops-taskboard-demo.git
cd devops-taskboard-demo
cp .env.example .env
# Замените DB_PASSWORD=CHANGE_ME_TO_RANDOM_HEX на случайный пароль.
sed -i "s/CHANGE_ME_TO_RANDOM_HEX/$(openssl rand -hex 24)/" .env
docker compose up -d --build --wait
docker compose ps
curl -fsS http://127.0.0.1:8080/readyz
```

Откройте `http://localhost:8080` (фронтенд) или `http://localhost:8080/docs` (Swagger).
Для остановки: `docker compose down`. Данные в PostgreSQL сохраняются в volume `postgres_data`; не используйте `down -v`, если хотите сохранить задачи.

## 2. Запуск без Docker

Требуются Python 3.12+ и pip. Локально используется SQLite.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
python -m pytest -q
uvicorn app.main:app --reload
```

Открыть `http://127.0.0.1:8000`.

## 3. CI/CD

Workflow: [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml).

- Pull Request в `main`: установка зависимостей, `pytest`, сборка Docker.
- Push в `main`: тесты → Docker build → публикация образа `ghcr.io/folcramus/devops-taskboard-demo:<commit-SHA>`.
- SSH-деплой доступен только при `DEPLOY_ENABLED=true` и настроенных secrets. **По умолчанию выключен**.

**Secrets:** `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS`. **Variable:** `DEPLOY_ENABLED`.

### Важное про GHCR

Workflow публикует образ через стандартный `GITHUB_TOKEN`; чтобы сервер мог его скачивать, сделайте пакет публичным либо настройте `docker login ghcr.io` для серверного пользователя с ограниченным `read:packages` токеном. Секреты никогда не коммитьте.

## 4. Сервер

Полная инструкция: [docs/DEPLOY.md](docs/DEPLOY.md). После подготовки сервера и секретов запустите `bash scripts/server-preflight.sh` на сервере и только после успешной проверки включите переменную `DEPLOY_ENABLED=true`.

Для ручного отката на сервере после хотя бы двух удачных релизов: `bash /opt/devops-taskboard/scripts/rollback.sh`.

## 5. API

| Method | Path | Описание |
| --- | --- | --- |
| GET | `/` | Веб-интерфейс |
| GET | `/healthz` | Liveness |
| GET | `/readyz` | Readiness и версия |
| GET | `/api/tasks` | Список задач |
| POST | `/api/tasks` | Создание |
| PATCH | `/api/tasks/{id}` | Отметить выполнение |
| DELETE | `/api/tasks/{id}` | Удалить |
| GET | `/api/stats` | Статистика |

**Примечание:** для production-проекта добавьте миграции Alembic, управление доступом, резервные копии, pinning версий зависимостей, HTTPS и мониторинг.

Учебный сценарий с объяснением команд: [docs/WORKSHOP.md](docs/WORKSHOP.md).
