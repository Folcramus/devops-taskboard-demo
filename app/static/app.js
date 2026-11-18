"use strict";
const $ = (id) => document.getElementById(id);
let tasks = [];
let filter = "all";

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(typeof body.detail === "string" ? body.detail : "Ошибка HTTP " + response.status);
  }
  return response.status === 204 ? null : response.json();
}

function render() {
  $("total").textContent = tasks.length;
  const completed = tasks.filter((task) => task.done).length;
  $("completed").textContent = completed;
  $("active").textContent = tasks.length - completed;
  const percent = tasks.length ? Math.round((completed / tasks.length) * 100) : 0;
  $("progress-label").textContent = percent + "%";
  $("progress").style.width = percent + "%";

  const visible = tasks.filter((t) => filter === "all" || (filter === "done" ? t.done : !t.done));
  $("tasks").replaceChildren();
  $("empty").hidden = visible.length !== 0;
  for (const task of visible) {
    const row = document.createElement("li");
    const check = document.createElement("input");
    check.type = "checkbox";
    check.checked = task.done;
    check.setAttribute("aria-label", "Выполнено: " + task.title);
    check.addEventListener("change", () => modify("/api/tasks/" + task.id, "PATCH", { done: check.checked }));

    const text = document.createElement("div");
    text.className = "task-text";
    const title = document.createElement("span");
    title.className = "task-title" + (task.done ? " done" : "");
    title.textContent = task.title;
    const meta = document.createElement("span");
    meta.className = "task-meta";
    meta.textContent = "Задача #" + task.id;
    text.append(title, meta);

    const badge = document.createElement("span");
    badge.className = "priority " + task.priority;
    badge.textContent = { high: "Важно", normal: "Обычно", low: "Низкий" }[task.priority];
    const del = document.createElement("button");
    del.type = "button";
    del.className = "remove";
    del.textContent = "Удалить";
    del.setAttribute("aria-label", "Удалить задачу " + task.title);
    del.addEventListener("click", () => modify("/api/tasks/" + task.id, "DELETE"));
    row.append(check, text, badge, del);
    $("tasks").append(row);
  }
}

async function refresh() {
  tasks = await api("/api/tasks");
  render();
}

async function modify(path, method, payload) {
  $("message").textContent = "";
  try {
    await api(path, { method, ...(payload ? { body: JSON.stringify(payload) } : {}) });
    await refresh();
  } catch (error) {
    $("message").textContent = error.message;
    await refresh().catch(() => {});
  }
}

async function refreshHealth() {
  try {
    const result = await api("/readyz");
    $("health-status").textContent = "● Сервис работает";
    $("health-status").className = "status-pill ok";
    $("version").textContent = result.version;
  } catch {
    $("health-status").textContent = "● Нет связи с БД";
    $("health-status").className = "status-pill fail";
  }
}

$("create-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const title = $("task-title").value.trim();
  if (!title) return;
  await modify("/api/tasks", "POST", { title, priority: $("priority").value });
  if (!$("message").textContent) $("task-title").value = "";
});

document.querySelectorAll("[data-filter]").forEach((button) => {
  button.addEventListener("click", () => {
    filter = button.dataset.filter;
    document.querySelectorAll("[data-filter]").forEach((item) => item.classList.toggle("selected", item === button));
    render();
  });
});

refresh().catch((error) => { $("message").textContent = error.message; });
refreshHealth();
setInterval(refreshHealth, 15000);
