# Сценарий демонстрации на мастер-классе DevOps

Рассчитан на 120 минут. В начале курса подготовьте локальный Docker и отдельную учебную Ubuntu VM.

| Минуты | Действие | Команда или результат |
| --- | --- | --- |
| 0–10 | Что такое DevOps | Dev → CI → CD → Ops → Observability |
| 10–20 | Запуск Python | `uvicorn app.main:app --reload` |
| 20–35 | Git | `git status`, `git diff`, `git add`, `git commit`, `git push` |
| 35–50 | Linux и SSH | `ssh deploy@SERVER`, `ss -tulpn`, `systemctl status docker` |
| 50–70 | Docker | `docker build -t taskboard:demo .`, `docker image ls` |
| 70–80 | Compose | `docker compose up -d --build --wait`, `docker compose ps` |
| 80–100 | CI/CD | GitHub Actions: tests → publish → gated deploy |
| 100–115 | Мониторинг и откат | `docker compose logs -f`, `curl /readyz`, `scripts/rollback.sh` |
| 115–120 | Итоги | Ответы на вопросы |

## Что показать на экран

1. С помощью `git clone` получить репозиторий на ноутбук.
2. `python3 -m venv .venv` — создать изолированное Python-окружение. `source .venv/bin/activate` — активировать его. `pip install -r requirements-dev.txt` — установить зависимости.
3. `pytest -q` — запустить тесты (создание, обновление, удаление и валидация задач).
4. `uvicorn app.main:app --reload` — запустить API напрямую. Показать `/docs`, `/readyz` и фронтенд.
5. `docker build -t taskboard:demo .` — создать образ из Dockerfile; объяснить base image, WORKDIR, COPY, RUN, CMD и HEALTHCHECK.
6. `docker run --rm -p 127.0.0.1:8001:8000 taskboard:demo` — запустить один контейнер на порту 8001 (без Postgres использует SQLite, данные эфемерны).
7. `docker compose up -d --build --wait` — поднять три сервиса: Nginx, FastAPI, PostgreSQL. Показать `docker compose ps`, `logs`, `docker volume ls`.
8. Изменить текст в `app/static/index.html`, затем выполнить `git add app/static/index.html`, `git commit -m "demo: update UI"`, `git push origin main`.
9. Открыть вкладку GitHub Actions, показать прохождение тестов и публикации immutable образа с тегом SHA коммита.
10. Для демонстрации CD сначала выполнить подготовку отдельной VM из [DEPLOY.md](DEPLOY.md). Без этого останется только CI и публикация.
11. На сервере показать `docker compose --env-file .env --env-file .release.env -f compose.prod.yaml ps` и `curl -fsS http://127.0.0.1:8080/readyz`.
12. Показать остановку контейнера БД и сообщения мониторинга, затем восстановление контейнера. Для примера отката после двух релизов — `bash scripts/rollback.sh`.

## Определения

- **Git** — распределённая система управления версиями.
- **SSH** — протокол безопасного удалённого управления сервером.
- **Docker image** — неизменяемый шаблон файловой системы и запуска приложения.
- **Container** — изолированный процесс, созданный из образа.
- **Volume** — постоянное хранилище вне жизненного цикла контейнера.
- **Docker Compose** — декларативное описание и запуск группы сервисов.
- **CI** — автоматические проверки при изменении кода.
- **CD** — автоматизированная доставка и/или развертывание.
- **GHCR** — GitHub Container Registry, хранилище OCI-образов.
- **GitHub Actions** — средство запуска workflow, jobs и steps на runners.
- **Reverse proxy** — прокси между пользователем и API, в проекте Nginx.
- **Healthcheck** — автоматическая проверка работоспособности.
- **Rollback** — возврат к предыдущему успешному релизу.

Не демонстрируйте приватные ключи и содержимое GitHub Secrets на проекторе.
