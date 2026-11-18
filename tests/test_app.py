def test_homepage_and_assets(client):
    assert client.get("/").status_code == 200
    assert "TaskBoard" in client.get("/").text
    assert "task-title" in client.get("/").text
    assert "fetch" in client.get("/static/app.js").text
    assert client.get("/static/styles.css").status_code == 200

def test_health_and_readiness(client):
    assert client.get("/healthz").json()["status"] == "ok"
    ready = client.get("/readyz")
    assert ready.status_code == 200
    assert ready.json()["database"] == "up"

def test_create_list_update_delete(client):
    created = client.post("/api/tasks", json={"title": "  Настроить CI/CD  ", "priority": "high"})
    assert created.status_code == 201
    item = created.json()
    assert item["title"] == "Настроить CI/CD"
    assert item["done"] is False
    assert item["priority"] == "high"
    path = f"/api/tasks/{item['id']}"
    assert client.get("/api/stats").json() == {"total": 1, "completed": 0, "active": 1}
    assert client.patch(path, json={"done": True}).json()["done"] is True
    assert client.get("/api/stats").json()["completed"] == 1
    assert len(client.get("/api/tasks").json()) == 1
    assert client.delete(path).status_code == 204
    assert client.get("/api/tasks").json() == []
    assert client.delete(path).status_code == 404

def test_validation(client):
    for title in ("", "    ", "x" * 161):
        assert client.post("/api/tasks", json={"title": title}).status_code == 422
    assert client.post("/api/tasks", json={"title": "demo", "priority": "urgent"}).status_code == 422
    assert client.patch("/api/tasks/42", json={"done": True}).status_code == 404
    assert client.patch("/api/tasks/42", json={"done": "sometimes"}).status_code == 422

def test_sql_injection_treated_as_text(client):
    payload = "x'); DROP TABLE tasks; --"
    result = client.post("/api/tasks", json={"title": payload})
    assert result.status_code == 201
    assert result.json()["title"] == payload
    assert client.get("/api/stats").json()["total"] == 1
