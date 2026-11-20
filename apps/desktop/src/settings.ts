// Settings sheet — ported from design/prototype/settings.html onto the
// engine settings RPCs and backup RPCs. Theme/language/default list are
// engine settings (single source); the global shortcut persists under the
// engine's free-form `global-quick-add` config key (slice 3 registers it).
import * as rpc from '@taskly/core';
import { t, setLang } from './i18n';
import * as store from './store';
import { announce, esc, TODAY } from './shared';
import { applyTheme } from './theme';
import { openDbDialog, revealDatabase } from './database-flow';

const DEFAULT_SHORTCUT = '⌃⌥Space';
let shortcut = DEFAULT_SHORTCUT;
let recording = false;
let pendingBackupPath: string | null = null;
let pendingPreview: rpc.BackupPreview | null = null;
let restoreDbPath: string | null = null;

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;

function report(message: string): void {
  $('dataFeedback').textContent = message;
  announce(message);
}

export async function openSettings(): Promise<void> {
  // language / theme / default list from engine settings
  ($('lang') as HTMLSelectElement).value = store.settings.language || 'system';
  document.querySelectorAll<HTMLInputElement>('#themeSeg input[name="theme"]').forEach((r) => {
    r.checked = r.value === (store.settings.theme || 'system');
  });
  const dl = $('defaultList') as HTMLSelectElement;
  dl.innerHTML = store.snapshot.lists.map((l) =>
    '<option value="' + l.id + '">' + esc(l.name) + '</option>').join('');
  dl.value = String(store.settings.defaultListId || (store.snapshot.lists[0]?.id ?? 0));
  try {
    shortcut = (await rpc.getSetting('global-quick-add')) || DEFAULT_SHORTCUT;
    if (shortcut === 'disabled') shortcut = '';
  } catch { shortcut = DEFAULT_SHORTCUT; }
  renderShortcut();
  $('settingsSheetWrap').hidden = false;
  $('settingsBack').focus();
}

function closeSettings(): void {
  $('settingsSheetWrap').hidden = true;
  stopRecording();
}

/* ---- shortcut recording (host registers it in slice 3) ---- */

function renderShortcut(): void {
  const btn = $('scBtn');
  btn.classList.toggle('empty', !shortcut);
  btn.classList.remove('rec');
  btn.textContent = shortcut || t('shortcutNone');
  $('scValue').textContent = shortcut || t('shortcutNone');
  ($('scReset') as HTMLButtonElement).disabled = shortcut === DEFAULT_SHORTCUT;
}

function stopRecording(): void {
  if (!recording) return;
  recording = false;
  renderShortcut();
}

function startRecording(): void {
  if (recording) return;
  recording = true;
  $('scBtn').classList.add('rec');
  $('scBtn').textContent = t('shortcutRecording');
  announce(t('shortcutRecording'));
}

function formatCombo(e: KeyboardEvent): string {
  const parts: string[] = [];
  if (e.ctrlKey) parts.push('⌃');
  if (e.altKey) parts.push('⌥');
  if (e.shiftKey) parts.push('⇧');
  if (e.metaKey) parts.push('⌘');
  let key = e.key;
  if (key === ' ' || key === 'Spacebar') key = 'Space';
  else if (key.length === 1) key = key.toUpperCase();
  return parts.join('') + key;
}

async function persistShortcut(value: string): Promise<void> {
  await rpc.setSetting('global-quick-add', value || 'disabled');
}

/* ---- data group ---- */

async function exportJson(): Promise<void> {
  if (!store.dbOpen) { report(t('taskListInputHintNoDb')); return; }
  const path = await store.host.saveFile(t('dbSaveBackup'), 'taskly-backup-' + TODAY + '.json', store.JSON_FILTERS);
  if (!path) return;
  try {
    const count = await store.exportBackup(path);
    report(t('dbExported', count));
  } catch (e) {
    report(t('dbRestoreInvalid', e instanceof Error ? e.message : String(e)));
  }
}

async function chooseRestore(): Promise<void> {
  if (!store.dbOpen) { report(t('taskListInputHintNoDb')); return; }
  const path = await store.host.pickFile(t('dbChooseBackup'), store.JSON_FILTERS);
  if (!path) return;
  try {
    const preview = await store.previewBackup(path);
    pendingBackupPath = path;
    pendingPreview = preview;
    restoreDbPath = store.settings.databasePath;
    $('restoreDescription').hidden = false;
    $('restoreDescription').textContent = t('dbRestorePreviewBody', preview.taskCount, preview.listCount);
    $<HTMLDialogElement>('dataDialog').showModal();
    $('dialogCancel').focus();
  } catch (e) {
    report(t('dbRestoreInvalid', e instanceof Error ? e.message : String(e)));
  }
}

async function applyRestore(): Promise<void> {
  const dialog = $<HTMLDialogElement>('dataDialog');
  if (!pendingBackupPath || store.settings.databasePath !== restoreDbPath) {
    report(t('dbRestoreStale'));
    dialog.close();
    return;
  }
  try {
    await store.restoreBackup(pendingBackupPath);
    report(t('dbRestored', pendingPreview ? pendingPreview.taskCount : 0));
  } catch (e) {
    report(t('dbRestoreInvalid', e instanceof Error ? e.message : String(e)));
  }
  dialog.close();
}

export function initSettings(): void {
  $('settingsBack').addEventListener('click', closeSettings);
  $('settingsSheetWrap').addEventListener('pointerdown', (e) => {
    if (e.target === $('settingsSheetWrap')) closeSettings();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('settingsSheetWrap').hidden && !recording) closeSettings();
  });

  $('lang').addEventListener('change', (e) => {
    const value = (e.target as HTMLSelectElement).value;
    void store.setSetting('language', value).then(() => {
      setLang(value === 'zh' ? 'zh' : 'en');
      store.emit();
    });
  });

  $('themeSeg').addEventListener('change', (e) => {
    const target = e.target as HTMLInputElement;
    if (target.name !== 'theme') return;
    void store.setSetting('theme', target.value).then(() => applyTheme(target.value));
  });

  $('defaultList').addEventListener('change', (e) => {
    const value = (e.target as HTMLSelectElement).value;
    void store.setSetting('default-list-id', value);
  });

  /* shortcut */
  $('scBtn').addEventListener('click', () => { recording ? stopRecording() : startRecording(); });
  document.addEventListener('keydown', (e) => {
    if (!recording) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.key === 'Escape') { stopRecording(); return; }
    if (['Shift', 'Control', 'Alt', 'Meta', 'CapsLock', 'Tab'].includes(e.key)) return;
    if (!e.ctrlKey && !e.altKey && !e.metaKey) { announce(t('shortcutNeedModifier')); return; }
    shortcut = formatCombo(e);
    void persistShortcut(shortcut);
    stopRecording();
  }, true);
  document.addEventListener('pointerdown', (e) => {
    if (recording && !$('scBtn').contains(e.target as Node)) stopRecording();
  });
  $('scBtn').addEventListener('blur', () => { if (recording) stopRecording(); });
  $('scReset').addEventListener('click', () => {
    stopRecording();
    shortcut = DEFAULT_SHORTCUT;
    void persistShortcut(shortcut);
    renderShortcut();
  });
  $('scClear').addEventListener('click', () => {
    stopRecording();
    shortcut = '';
    void persistShortcut('');
    renderShortcut();
  });

  /* data */
  $('exportBtn').addEventListener('click', () => { void exportJson(); });
  $('restoreBtn').addEventListener('click', () => { void chooseRestore(); });
  $('dialogCancel').addEventListener('click', () => $<HTMLDialogElement>('dataDialog').close());
  $('dialogApply').addEventListener('click', () => { void applyRestore(); });
  $<HTMLDialogElement>('dataDialog').addEventListener('close', () => {
    pendingBackupPath = null;
    pendingPreview = null;
    restoreDbPath = null;
  });
  document.querySelectorAll<HTMLElement>('[data-db-action="migrate"],[data-db-action="open"],[data-db-action="create"]').forEach((b) => {
    // handled by database-flow's delegated listener; nothing extra here
    void b;
  });
  void openDbDialog; void revealDatabase;
}