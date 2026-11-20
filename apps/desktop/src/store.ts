// Engine-backed data layer for the single web UI (#141).
//
// The Racket engine owns all state: every mutation is a typed RPC from
// rivet-schema.json, followed by a snapshot refetch (the engine declares
// `changed` but does not emit it yet). Views filter the full snapshot
// client-side exactly like the prototype; search rides search_tasks.
import * as rpc from '@taskly/core';
import { apiPost } from '@taskly/core';
import type { Settings, Snapshot, Task, TodoList } from '@taskly/core';
import { bucket, extractTags, TODAY } from './shared';

export type ViewKind = 'today' | 'planned' | 'all' | 'completed' | 'list';

export interface ViewState {
  view: ViewKind;
  listId: number | null;
  tag: string | null;
  q: string;
  doneOpen: boolean;
}

export const state: ViewState = { view: 'today', listId: null, tag: null, q: '', doneOpen: true };

export const EMPTY_SNAPSHOT: Snapshot = {
  counts: { today: 0, planned: 0, all: 0, completed: 0 },
  lists: [],
  tasks: [],
};

export const DEFAULT_SETTINGS: Settings = {
  language: 'system',
  theme: 'system',
  closeToTray: 'false',
  lastSelectedListId: 0,
  databasePath: '',
  databaseName: '',
  defaultListId: 0,
};

export let snapshot: Snapshot = EMPTY_SNAPSHOT;
export let settings: Settings = DEFAULT_SETTINGS;
export let dbOpen = false;
export let searchResults: Task[] | null = null;

const listeners = new Set<() => void>();
export function onChange(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
export function emit(): void {
  listeners.forEach((fn) => fn());
}

export function taskById(id: number): Task | undefined {
  return snapshot.tasks.find((t) => t.id === id);
}
export function listById(id: number | null): TodoList | undefined {
  return snapshot.lists.find((l) => l.id === id);
}

export function inView(t: Task): boolean {
  if (state.tag && !t.tags.includes(state.tag)) return false;
  if (state.view === 'today') { const b = bucket(t); return b === 'today' || b === 'over'; }
  if (state.view === 'planned') return !!t.dueDate;
  if (state.view === 'completed') return t.completed;
  if (state.view === 'list') return t.listId === state.listId;
  return true;
}

/** Rows for the current view: engine search results, or filtered snapshot. */
export function visible(): Task[] {
  if (state.q && searchResults) return searchResults.filter((t) => !state.tag || t.tags.includes(state.tag));
  return snapshot.tasks.filter(inView);
}

export function tagCounts(): Map<string, number> {
  const m = new Map<string, number>();
  for (const t of snapshot.tasks) {
    if (t.completed) continue;
    for (const g of t.tags) m.set(g, (m.get(g) || 0) + 1);
  }
  return m;
}

/** Refetch everything the UI renders. Called after every mutation. */
export async function refresh(): Promise<void> {
  snapshot = await rpc.loadSnapshot('all', null, true);
  settings = await rpc.getSettings();
  searchResults = state.q ? await rpc.searchTasks(state.q) : null;
  emit();
}

export type BootResult = { mode: 'ok' } | { mode: 'gate' | 'recovery'; error: string };

/** Startup gate (PRODUCT-SPEC §2a): open the remembered database, or gate. */
export async function boot(): Promise<BootResult> {
  const path = await rpc.defaultDatabase();
  try {
    snapshot = await rpc.openDatabase(path);
    settings = await rpc.getSettings();
    dbOpen = true;
    emit();
    return { mode: 'ok' };
  } catch (e) {
    dbOpen = false;
    try { settings = await rpc.getSettings(); } catch { settings = DEFAULT_SETTINGS; }
    emit();
    const error = e instanceof Error ? e.message : String(e);
    const missing = /not found|no such file|不存在/i.test(error);
    // settings.databasePath is always the resolved default; only the
    // config's remembered last-db-path proves a previous connection.
    let remembered = '';
    try { remembered = await rpc.getSetting('last-db-path'); } catch { /* fresh config */ }
    if (missing && remembered) return { mode: 'recovery', error: '' };
    return { mode: 'gate', error: missing ? '' : error };
  }
}

/* ---- mutations: RPC → refetch → render; errors surface to the caller ---- */

export async function toggleTask(id: number, completed: boolean): Promise<void> {
  await rpc.setCompleted(id, completed);
  await refresh();
}

export async function saveTask(task: Task): Promise<void> {
  await rpc.updateTask(task);
  await refresh();
}

export async function saveTaskText(id: number, text: string): Promise<void> {
  await rpc.updateTaskText(id, text);
  await refresh();
}

export async function removeTask(id: number): Promise<Task | undefined> {
  const gone = taskById(id);
  await rpc.deleteTask(id);
  await refresh();
  return gone;
}

/** Undo = re-create with all fields (the engine has no tombstone RPC). */
export async function undoRemove(t: Task): Promise<void> {
  const created = await rpc.addTask(t.text, t.listId, t.dueDate, t.dueTime, t.notes);
  await rpc.updateTask({ ...created, completed: t.completed, priority: t.priority, tags: t.tags, subtasks: t.subtasks, url: t.url });
  await refresh();
}

export async function quickAdd(raw: string): Promise<Task | null> {
  const parsed = await rpc.parseQuickAdd(raw);
  const fromRaw = extractTags(raw);
  const clean = extractTags(parsed.text);
  const title = clean.title || fromRaw.title;
  if (!title) return null;
  const tags = fromRaw.tags;
  if (state.tag && !tags.includes(state.tag)) tags.push(state.tag);
  const listId = state.view === 'list' ? state.listId : settings.defaultListId || null;
  let created = await rpc.addTask(title, listId, parsed.dueDate, parsed.dueTime, null);
  if (tags.length) created = await rpc.updateTask({ ...created, tags });
  await refresh();
  return created;
}

export async function createList(name: string, icon: string, color: number): Promise<TodoList> {
  const l = await rpc.createList(name, icon, color);
  await refresh();
  return l;
}

export async function saveList(item: TodoList): Promise<void> {
  await rpc.updateList(item);
  await refresh();
}

export async function removeList(id: number): Promise<void> {
  await rpc.deleteList(id);
  if (state.view === 'list' && state.listId === id) { state.view = 'all'; state.listId = null; }
  await refresh();
}

export async function setSetting(key: string, value: string): Promise<void> {
  settings = await rpc.setSetting(key, value);
  emit();
}

/* ---- database lifecycle ---- */

export async function createDb(folder: string, name: string): Promise<void> {
  snapshot = await rpc.createDatabase(folder, name);
  settings = await rpc.getSettings();
  dbOpen = true;
  resetView();
  emit();
}

export async function openDb(path: string): Promise<void> {
  snapshot = await rpc.openDatabase(path);
  settings = await rpc.getSettings();
  dbOpen = true;
  resetView();
  emit();
}

export async function migrateDb(folder: string): Promise<void> {
  snapshot = await rpc.migrateDatabase(folder);
  settings = await rpc.getSettings();
  emit();
}

export async function closeDb(): Promise<void> {
  await rpc.closeDatabase();
  dbOpen = false;
  snapshot = EMPTY_SNAPSHOT;
  resetView();
  emit();
}

export function resetView(): void {
  state.view = 'today'; state.listId = null; state.tag = null; state.q = '';
  searchResults = null;
}

export async function setSearch(q: string): Promise<void> {
  state.q = q;
  searchResults = q ? await rpc.searchTasks(q) : null;
  emit();
}

/* ---- backup / restore ---- */

export async function exportBackup(path: string): Promise<number> {
  return rpc.exportBackup(path);
}
export async function previewBackup(path: string): Promise<rpc.BackupPreview> {
  return rpc.previewBackup(path);
}
export async function restoreBackup(path: string): Promise<void> {
  snapshot = await rpc.restoreBackup(path);
  settings = await rpc.getSettings();
  resetView();
  emit();
}

/* ---- host capabilities (native pickers / reveal; not engine RPCs) ---- */

export const host = {
  pickFolder(title?: string): Promise<string | null> {
    return apiPost('/api/host/pick_folder', { title: title ?? null });
  },
  pickFile(title?: string, filters?: string[][]): Promise<string | null> {
    return apiPost('/api/host/pick_file', { title: title ?? null, filters: filters ?? [] });
  },
  saveFile(title?: string, defaultName?: string, filters?: string[][]): Promise<string | null> {
    return apiPost('/api/host/save_file', { title: title ?? null, defaultName: defaultName ?? null, filters: filters ?? [] });
  },
  reveal(path: string): Promise<boolean> {
    return apiPost('/api/host/reveal', { path });
  },
};

export const DB_FILTERS = [['Taskly database', '*.sqlite', '*.sqlite3', '*.db']];
export const JSON_FILTERS = [['JSON backup', '*.json']];

export { TODAY };