// Taskly desktop shell — slice 1 of the glaze rewrite (#141).
// A minimal but real UI over the typed RPC client: boot the default
// database, render the snapshot, quick-add / complete / delete tasks.
// Slice 2 evolves this into the design/prototype UI (shared.css tokens,
// i18n, detail panels, settings); the RPC surface stays identical.
import {
  defaultDatabase,
  openDatabase,
  createDatabase,
  loadSnapshot,
  addTask,
  setCompleted,
  deleteTask,
  type Snapshot,
  type Task,
} from '@taskly/core';
import './style.css';

const app = document.querySelector<HTMLDivElement>('#app')!;

let snapshot: Snapshot | null = null;
let view = 'all';
let listId: number | null = null;
let showCompleted = true;
let busy = false;

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className?: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

async function refresh(): Promise<void> {
  snapshot = await loadSnapshot(view, listId, showCompleted);
  render();
}

async function mutate(fn: () => Promise<unknown>): Promise<void> {
  if (busy) return;
  busy = true;
  try {
    await fn();
    await refresh();
  } catch (e) {
    showError(e instanceof Error ? e.message : String(e));
  } finally {
    busy = false;
  }
}

function showError(message: string): void {
  const bar = document.querySelector<HTMLElement>('.error-bar');
  if (bar) {
    bar.textContent = message;
    bar.hidden = false;
  }
}

function render(): void {
  app.textContent = '';
  if (!snapshot) return;

  const sidebar = el('aside', 'sidebar');
  const counts = snapshot.counts;
  const smart: Array<[string, string, number]> = [
    ['today', 'Today', counts.today],
    ['planned', 'Planned', counts.planned],
    ['all', 'All', counts.all],
    ['completed', 'Completed', counts.completed],
  ];
  for (const [key, label, count] of smart) {
    const item = el('button', `nav-item${view === key && listId === null ? ' active' : ''}`);
    item.append(el('span', 'nav-label', label), el('span', 'nav-count', String(count)));
    item.addEventListener('click', () => {
      view = key;
      listId = null;
      void refresh();
    });
    sidebar.append(item);
  }
  sidebar.append(el('div', 'nav-section', 'Lists'));
  for (const list of snapshot.lists) {
    const item = el('button', `nav-item${listId === list.id ? ' active' : ''}`);
    item.append(
      el('span', 'nav-label', `${list.icon ?? '📋'} ${list.name}`),
      el('span', 'nav-count', String(list.pendingCount)),
    );
    item.addEventListener('click', () => {
      view = 'all';
      listId = list.id;
      void refresh();
    });
    sidebar.append(item);
  }

  const main = el('main', 'main');
  const errorBar = el('div', 'error-bar');
  errorBar.hidden = true;
  main.append(errorBar);

  const quickAdd = el('input', 'quick-add') as HTMLInputElement;
  quickAdd.placeholder = 'Add a task… (try "pay rent @tomorrow 10am")';
  quickAdd.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && quickAdd.value.trim()) {
      const text = quickAdd.value.trim();
      quickAdd.value = '';
      void mutate(() => addTask(text, listId, null, null, null));
    }
  });
  main.append(quickAdd);

  const list = el('div', 'task-list');
  for (const task of snapshot.tasks) {
    list.append(taskRow(task));
  }
  if (snapshot.tasks.length === 0) {
    list.append(el('div', 'empty', 'Nothing here yet.'));
  }
  main.append(list);

  app.append(sidebar, main);
}

function taskRow(task: Task): HTMLElement {
  const row = el('div', `task-row${task.completed ? ' done' : ''}`);
  const check = el('input', 'task-check') as HTMLInputElement;
  check.type = 'checkbox';
  check.checked = task.completed;
  check.addEventListener('change', () =>
    void mutate(() => setCompleted(task.id, check.checked)),
  );
  const body = el('div', 'task-body');
  body.append(el('div', 'task-text', task.text));
  const meta: string[] = [];
  if (task.dueDate) meta.push(task.dueTime ? `${task.dueDate} ${task.dueTime}` : task.dueDate);
  if (task.listName) meta.push(task.listName);
  if (meta.length) body.append(el('div', 'task-meta', meta.join(' · ')));
  const del = el('button', 'task-delete', '✕');
  del.title = 'Delete task';
  del.addEventListener('click', () => void mutate(() => deleteTask(task.id)));
  row.append(check, body, del);
  return row;
}

async function boot(): Promise<void> {
  const path = await defaultDatabase();
  try {
    await openDatabase(path);
  } catch {
    // First run: create the default database in its resolved folder.
    const sep = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    const folder = sep > 0 ? path.slice(0, sep) : '.';
    await createDatabase(folder, 'Taskly');
  }
  await refresh();
}

void boot().catch((e) => {
  app.textContent = '';
  app.append(el('div', 'fatal', `Taskly failed to start: ${e instanceof Error ? e.message : e}`));
});