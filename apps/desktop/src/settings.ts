// Settings sheet — ported from design/prototype/settings.html onto the
// engine settings RPCs and backup RPCs. Theme/language/default list are
// engine settings (single source); the global shortcut persists under the
// engine's free-form `global-quick-add` config key as a glaze accelerator
// ("Ctrl+Alt+Space") and the thin host registers it with the OS (slice 3).
import * as rpc from '@taskly/core';
import { t, setLang } from './i18n';
import * as store from './store';
import { announce, esc, TODAY } from './shared';
import { applyTheme } from './theme';
import { openDbDialog, revealDatabase } from './database-flow';

const DEFAULT_ACCEL = 'Ctrl+Alt+Space';
let shortcut = DEFAULT_ACCEL;
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
  ($('lang') as HTMLSelectElement).value = store.settings.language || 'zh';
  document.querySelectorAll<HTMLInputElement>('#themeSeg input[name="theme"]').forEach((r) => {
    r.checked = r.value === (store.settings.theme || 'system');
  });
  const dl = $('defaultList') as HTMLSelectElement;
  dl.innerHTML = store.snapshot.lists.map((l) =>
    '<option value="' + l.id + '">' + esc(l.name) + '</option>').join('');
  dl.value = String(store.settings.defaultListId || (store.snapshot.lists[0]?.id ?? 0));
  ($('closeTrayChk') as HTMLInputElement).checked = store.settings.closeToTray !== '0';
  try {
    const state = await store.host.autostart();
    const chk = $('autostartChk') as HTMLInputElement;
    chk.checked = state.enabled === true;
    chk.disabled = !state.installed;
    $('autostartHelp').textContent = state.installed ? t('autostartHelp') : t('autostartDevNote');
  } catch { /* host capability unavailable (pure web dev) */ }
  try {
    shortcut = (await rpc.getSetting('global-quick-add')) || DEFAULT_ACCEL;
    if (shortcut === 'disabled') shortcut = '';
  } catch { shortcut = DEFAULT_ACCEL; }
  renderShortcut();
  $('settingsSheetWrap').hidden = false;
  $('settingsBack').focus();
  void refreshAbout();
}

/* ---- About + update check (#157) ---- */
// The web UI checks and hands over to the releases page; it never downloads
// or installs. The engine owns `auto-check-updates` and the
// `last-update-check` stamp (unix seconds, shared/spec/UPDATE.md), so this
// module keeps nothing that has to survive a restart.
type UpdState = 'idle' | 'checking' | 'up-to-date' | 'available' | 'error';
interface UpdView { state: UpdState; error: string | null; version: string | null; publishedAt: string | null; }

const RELEASES_URL = 'https://github.com/turlamai/taskly/releases/latest';
const CHECK_THROTTLE_S = 4 * 60 * 60;

let appInfo: rpc.AppInfo | null = null;
let upd: UpdView = { state: 'idle', error: null, version: null, publishedAt: null };
let lastCheckEpoch = 0;
let diagText = '';
// Real network attempts (manual or unthrottled silent); acceptance reads it.
let attempts = 0;

/** Current update-check state (read-only view for acceptance). */
export function updateView(): Readonly<UpdView> { return upd; }
export function updateAttempts(): number { return attempts; }

function loadAppInfo(): Promise<rpc.AppInfo> {
  if (appInfo) return Promise.resolve(appInfo);
  return rpc.appInfo().then((info) => { appInfo = info; return info; });
}

function publishedOn(value: string | null): string {
  return value && /^\d{4}-\d{2}-\d{2}/.test(value) ? value.slice(0, 10) : (value || '—');
}

/** Open an https Taskly link in the system browser (host whitelist applies). */
export async function openExternal(url: string): Promise<void> {
  let ok = false;
  try { ok = await store.host.openUrl(url); } catch { ok = false; }
  if (!ok) announce(t('updOpenFailed', url));
}

export async function checkForUpdates(reason: 'manual' | 'silent'): Promise<void> {
  if (upd.state === 'checking') return;
  if (reason === 'silent') {
    // Silent checks respect the toggle and the 4-hour stamp; manual ones always run.
    try {
      if ((await rpc.getSetting('auto-check-updates')) === '0') return;
      const last = Number(await rpc.getSetting('last-update-check')) || 0;
      if (Math.floor(Date.now() / 1000) - last < CHECK_THROTTLE_S) return;
    } catch { return; }
  }
  attempts += 1;
  upd = { state: 'checking', error: null, version: null, publishedAt: null };
  renderUpdate();
  try {
    const r = await rpc.checkUpdates();
    lastCheckEpoch = Math.floor(Date.now() / 1000);
    if (r.status === 'available') {
      upd = { state: 'available', error: null, version: r.availableVersion, publishedAt: r.publishedAt };
    } else if (r.status === 'up-to-date') {
      upd = { state: 'up-to-date', error: null, version: null, publishedAt: null };
    } else {
      upd = { state: 'error', error: r.error || r.status, version: null, publishedAt: null };
    }
  } catch (e) {
    upd = { state: 'error', error: e instanceof Error ? e.message : String(e), version: null, publishedAt: null };
  }
  if (reason === 'silent') {
    // Stamp only after a real attempt; failures count so an offline launch
    // does not retry on every window.
    try { await rpc.setSetting('last-update-check', String(lastCheckEpoch)); } catch { /* stamp is best-effort */ }
  }
  renderUpdate();
  if (reason === 'manual') announce($('updHelp').textContent || '');
}

function renderUpdate(): void {
  const help = $('updHelp');
  const btn = $('updBtn') as HTMLButtonElement;
  help.classList.remove('ok', 'err');
  switch (upd.state) {
    case 'checking':
      btn.textContent = t('updChecking'); btn.disabled = true; help.textContent = t('updChecking'); break;
    case 'up-to-date':
      btn.textContent = t('menuCheckUpdates'); btn.disabled = false;
      help.classList.add('ok'); help.textContent = t('updUpToDate'); break;
    case 'available':
      btn.textContent = t('updGoDownload'); btn.disabled = false;
      help.textContent = t('updAvailableHelp', upd.version || '', publishedOn(upd.publishedAt)); break;
    case 'error':
      btn.textContent = t('updRetry'); btn.disabled = false;
      help.classList.add('err'); help.textContent = t('updErrorHelp', upd.error || ''); break;
    default:
      btn.textContent = t('menuCheckUpdates'); btn.disabled = false; help.textContent = t('updIdleHelp');
  }
  $('updPill').hidden = upd.state !== 'available';
}

function buildDiagnostics(auto: string, last: string): string {
  const i = appInfo;
  return [
    'Taskly ' + (i?.version ?? '?') + ' (' + (i?.platform ?? '?') + ' ' + (i?.architecture ?? '?') + ')',
    'language: ' + (store.settings.language || 'system') + '  theme: ' + (store.settings.theme || 'system'),
    'auto-check-updates: ' + auto + '  last-update-check: ' + (last || 'never'),
    'database: ' + (i?.databasePath ?? '?'),
    'config: ' + (i?.configPath ?? '?'),
  ].join('\n');
}

async function refreshAbout(): Promise<void> {
  let auto = '1';
  let last = '';
  let info: rpc.AppInfo | null = null;
  try {
    [auto, last] = await Promise.all([rpc.getSetting('auto-check-updates'), rpc.getSetting('last-update-check')]);
  } catch { /* defaults above */ }
  try { info = await loadAppInfo(); } catch { /* host without the route: leave blank */ }
  $('aboutVer').textContent = info ? info.version : '';
  $('aboutTag').innerHTML = esc(t('aboutContent')).replace(/\n/g, '<br>');
  ($('updAutoChk') as HTMLInputElement).checked = auto !== '0';
  lastCheckEpoch = Number(last) || 0;
  diagText = buildDiagnostics(auto, last);
  $('diagPre').textContent = diagText;
  const copied = $('diagCopied');
  copied.textContent = '';
  renderUpdate();
  if (upd.state === 'idle') {
    const lastDate = lastCheckEpoch ? new Date(lastCheckEpoch * 1000).toLocaleString() : '';
    if (lastDate) $('updHelp').textContent = t('diagLastCheck', lastDate);
  }
}

async function copyDiagnostics(): Promise<void> {
  const copied = $('diagCopied');
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(diagText);
    } else {
      const area = document.createElement('textarea');
      area.value = diagText; area.setAttribute('readonly', ''); area.style.position = 'fixed'; area.style.opacity = '0';
      document.body.appendChild(area); area.select();
      document.execCommand('copy'); area.remove();
    }
    copied.textContent = t('diagCopied');
  } catch {
    copied.textContent = t('updateCopyError');
  }
  announce(copied.textContent || '');
}

function initAbout(): void {
  $('aboutLinks').querySelectorAll<HTMLButtonElement>('[data-href]').forEach((b) => {
    b.addEventListener('click', () => { void openExternal(b.dataset.href || ''); });
  });
  $('updBtn').addEventListener('click', () => {
    if (upd.state === 'available') { void openExternal(RELEASES_URL); return; }
    void checkForUpdates('manual');
  });
  $('updAutoChk').addEventListener('change', (e) => {
    const on = (e.target as HTMLInputElement).checked;
    void store.setSetting('auto-check-updates', on ? '1' : '0').then(() => { void refreshAbout(); });
  });
  $('diagCopy').addEventListener('click', () => { void copyDiagnostics(); });
}

/** Launch check: silent, throttled by the engine-stored stamp. */
export function silentUpdateCheck(): void {
  void checkForUpdates('silent');
}

function closeSettings(): void {
  $('settingsSheetWrap').hidden = true;
  stopRecording();
}

/* ---- shortcut recording (accelerator string; host registers it) ---- */

const MOD_GLYPHS: Record<string, string> = { Ctrl: '⌃', Alt: '⌥', Shift: '⇧', Cmd: '⌘', Meta: '⌘' };

function accelToDisplay(accel: string): string {
  return accel.split('+').map((p) => MOD_GLYPHS[p] || p).join('');
}

function renderShortcut(): void {
  const btn = $('scBtn');
  btn.classList.toggle('empty', !shortcut);
  btn.classList.remove('rec');
  btn.textContent = shortcut ? accelToDisplay(shortcut) : t('shortcutNone');
  $('scValue').textContent = shortcut ? accelToDisplay(shortcut) : t('shortcutNone');
  ($('scReset') as HTMLButtonElement).disabled = shortcut === DEFAULT_ACCEL;
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

const KEY_NAMES: Record<string, string> = {
  ' ': 'Space', Spacebar: 'Space',
  ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
};

function formatCombo(e: KeyboardEvent): string {
  const parts: string[] = [];
  if (e.ctrlKey) parts.push('Ctrl');
  if (e.altKey) parts.push('Alt');
  if (e.shiftKey) parts.push('Shift');
  if (e.metaKey) parts.push('Cmd');
  let key = KEY_NAMES[e.key] || e.key;
  if (key.length === 1) key = key.toUpperCase();
  return parts.concat([key]).join('+');
}

async function persistShortcut(value: string): Promise<void> {
  await rpc.setSetting('global-quick-add', value || 'disabled');
  try {
    await store.host.shortcut(value);
  } catch (e) {
    // Recorded but refused by the OS (taken accelerator, headless session):
    // say so; the recording retries at next launch.
    announce(t('shortcutRegisterFailed', e instanceof Error ? e.message : String(e)));
  }
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
    const msg = e instanceof Error ? e.message : String(e);
    report(msg === 'stale-preview' ? t('dbRestoreStale') : t('dbRestoreInvalid', msg));
  }
  dialog.close();
}

export function initSettings(): void {
  initAbout();
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
      void refreshAbout();
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

  $('closeTrayChk').addEventListener('change', (e) => {
    const on = (e.target as HTMLInputElement).checked;
    void store.setSetting('close-to-tray', on ? '1' : '0');
  });

  $('autostartChk').addEventListener('change', (e) => {
    const chk = e.target as HTMLInputElement;
    const on = chk.checked;
    void store.host.setAutostart(on).then((state) => {
      chk.checked = state.enabled === true;
      report(t('autostartSaved'));
    }).catch((err) => {
      chk.checked = !on;
      report(t('autostartFailed', err instanceof Error ? err.message : String(err)));
    });
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
    shortcut = DEFAULT_ACCEL;
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