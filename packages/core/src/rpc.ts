// Generated from rivet-schema.json by scripts/gen-rpc-types.py — do not edit.
// Regenerate: pnpm gen:rpc (review the diff; the schema is the single source).

import { apiPost } from './bridge';

// ---- records (camelCase DTOs; field order on the wire is the schema's) ----

export interface AppInfo {
  version: string;
  platform: string;
  architecture: string;
  databasePath: string;
  configPath: string;
}

export interface BackupPreview {
  format: string;
  version: number;
  listCount: number;
  taskCount: number;
}

export interface QuickAddParse {
  text: string;
  dueDate: string | null;
  dueTime: string | null;
}

export interface ReminderDecision {
  token: string;
  kind: string;
  count: number;
  task: Task | null;
}

export interface Settings {
  language: string;
  theme: string;
  closeToTray: string;
  lastSelectedListId: number;
  databasePath: string;
  databaseName: string;
  defaultListId: number;
}

export interface SmartCounts {
  today: number;
  planned: number;
  all: number;
  completed: number;
}

export interface Snapshot {
  counts: SmartCounts;
  lists: Array<TodoList>;
  tasks: Array<Task>;
}

export interface Subtask {
  text: string;
  done: boolean;
}

export interface Task {
  id: number;
  listId: number;
  listName: string | null;
  text: string;
  completed: boolean;
  dueDate: string | null;
  dueTime: string | null;
  notes: string | null;
  createdAt: string;
  priority: number;
  tags: Array<string>;
  subtasks: Array<Subtask>;
  url: string | null;
}

export interface TodoList {
  id: number;
  name: string;
  icon: string | null;
  color: number | null;
  pendingCount: number;
}

export interface UpdateCheck {
  status: string;
  error: string | null;
  currentVersion: string;
  availableVersion: string | null;
  build: number | null;
  publishedAt: string | null;
  installer: string | null;
  sizeBytes: number | null;
}

export interface UpdateState {
  phase: string;
  percent: number;
  message: string | null;
  downloadedPath: string | null;
  availableVersion: string | null;
}

// ---- RPC surface ----

export const RPC_NAMES = [
  'acknowledge_reminder',
  'add_task',
  'app_info',
  'check_updates',
  'close_database',
  'create_database',
  'create_list',
  'default_database',
  'delete_list',
  'delete_task',
  'export_backup',
  'get_setting',
  'get_settings',
  'load_snapshot',
  'migrate_database',
  'open_database',
  'parse_due',
  'parse_quick_add',
  'preview_backup',
  'reminder_decisions',
  'restore_backup',
  'search_tasks',
  'set_completed',
  'set_setting',
  'start_download',
  'update_list',
  'update_state',
  'update_task',
  'update_task_text',
] as const;

export function acknowledgeReminder(token: string, phase: string): Promise<boolean> {
  return apiPost<boolean>('api/rpc/acknowledge_reminder', { token, phase });
}

export function addTask(text: string, listId: number | null, dueDate: string | null, dueTime: string | null, notes: string | null): Promise<Task> {
  return apiPost<Task>('api/rpc/add_task', { text, listId: listId ?? null, dueDate: dueDate ?? null, dueTime: dueTime ?? null, notes: notes ?? null });
}

export function appInfo(): Promise<AppInfo> {
  return apiPost<AppInfo>('api/rpc/app_info', {  });
}

export function checkUpdates(): Promise<UpdateCheck> {
  return apiPost<UpdateCheck>('api/rpc/check_updates', {  });
}

export function closeDatabase(): Promise<void> {
  return apiPost<null>('api/rpc/close_database', {  }).then(() => undefined);
}

export function createDatabase(folder: string, name: string): Promise<Snapshot> {
  return apiPost<Snapshot>('api/rpc/create_database', { folder, name });
}

export function createList(name: string, icon: string | null, color: number | null): Promise<TodoList> {
  return apiPost<TodoList>('api/rpc/create_list', { name, icon: icon ?? null, color: color ?? null });
}

export function defaultDatabase(): Promise<string> {
  return apiPost<string>('api/rpc/default_database', {  });
}

export function deleteList(id: number): Promise<boolean> {
  return apiPost<boolean>('api/rpc/delete_list', { id });
}

export function deleteTask(id: number): Promise<boolean> {
  return apiPost<boolean>('api/rpc/delete_task', { id });
}

export function exportBackup(path: string): Promise<number> {
  return apiPost<number>('api/rpc/export_backup', { path });
}

export function getSetting(key: string): Promise<string> {
  return apiPost<string>('api/rpc/get_setting', { key });
}

export function getSettings(): Promise<Settings> {
  return apiPost<Settings>('api/rpc/get_settings', {  });
}

export function loadSnapshot(view: string, listId: number | null, showCompleted: boolean): Promise<Snapshot> {
  return apiPost<Snapshot>('api/rpc/load_snapshot', { view, listId: listId ?? null, showCompleted });
}

export function migrateDatabase(folder: string): Promise<Snapshot> {
  return apiPost<Snapshot>('api/rpc/migrate_database', { folder });
}

export function openDatabase(path: string): Promise<Snapshot> {
  return apiPost<Snapshot>('api/rpc/open_database', { path });
}

export function parseDue(expression: string): Promise<string> {
  return apiPost<string>('api/rpc/parse_due', { expression });
}

export function parseQuickAdd(text: string): Promise<QuickAddParse> {
  return apiPost<QuickAddParse>('api/rpc/parse_quick_add', { text });
}

export function previewBackup(path: string): Promise<BackupPreview> {
  return apiPost<BackupPreview>('api/rpc/preview_backup', { path });
}

export function reminderDecisions(startup: boolean): Promise<Array<ReminderDecision>> {
  return apiPost<Array<ReminderDecision>>('api/rpc/reminder_decisions', { startup });
}

export function restoreBackup(path: string): Promise<Snapshot> {
  return apiPost<Snapshot>('api/rpc/restore_backup', { path });
}

export function searchTasks(keyword: string): Promise<Array<Task>> {
  return apiPost<Array<Task>>('api/rpc/search_tasks', { keyword });
}

export function setCompleted(id: number, completed: boolean): Promise<Task> {
  return apiPost<Task>('api/rpc/set_completed', { id, completed });
}

export function setSetting(key: string, value: string): Promise<Settings> {
  return apiPost<Settings>('api/rpc/set_setting', { key, value });
}

export function startDownload(): Promise<void> {
  return apiPost<null>('api/rpc/start_download', {  }).then(() => undefined);
}

export function updateList(item: TodoList): Promise<TodoList> {
  return apiPost<TodoList>('api/rpc/update_list', { item });
}

export function updateState(): Promise<UpdateState> {
  return apiPost<UpdateState>('api/rpc/update_state', {  });
}

export function updateTask(task: Task): Promise<Task> {
  return apiPost<Task>('api/rpc/update_task', { task });
}

export function updateTaskText(id: number, text: string): Promise<Task> {
  return apiPost<Task>('api/rpc/update_task_text', { id, text });
}
