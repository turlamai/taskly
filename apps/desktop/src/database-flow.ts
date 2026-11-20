// Database lifecycle gate + dialog, ported from design/prototype/
// database-flow.js onto the engine RPCs (create/open/migrate) and the
// native pickers (glaze dialogs via host routes). PRODUCT-SPEC §2a:
// startup gate, exclusive create, two-step migrate, no silent overwrite.
import { t } from './i18n';
import * as store from './store';
import { announce, esc } from './shared';

type Mode = 'create' | 'open' | 'migrate' | 'relocate';

let mode: Mode = 'create';
let confirmMigration = false;
let gateMode: 'gate' | 'recovery' = 'gate';
let gateError = '';
let chosenPath = '';
let trigger: HTMLElement | null = null;

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;

function dialog(): HTMLDialogElement { return $<HTMLDialogElement>('databaseDialog'); }

function fail(text: string): void {
  const err = $('databaseError');
  err.hidden = false;
  err.textContent = text;
  $('databasePath').setAttribute('aria-invalid', 'true');
}
function clearError(): void {
  const err = $('databaseError');
  err.hidden = true;
  err.textContent = '';
  $('databasePath').removeAttribute('aria-invalid');
}

export function setGateMode(m: 'gate' | 'recovery', error = ''): void {
  gateMode = m;
  gateError = error;
  refreshDatabaseUI();
}

export function refreshDatabaseUI(): void {
  const root = $('app');
  const app = root.querySelector<HTMLElement>('.app');
  const gate = $('databaseGate');
  if (app) app.hidden = !store.dbOpen;
  gate.hidden = store.dbOpen;
  const recovery = $('databaseRecovery');
  recovery.hidden = gateMode !== 'recovery';
  $('databaseMissingPath').textContent = store.settings.databasePath || t('dbMissingPathFallback');
  $('databaseWelcomeTitle').textContent = gateMode === 'recovery' ? t('dbReconnectTitle') : t('dbGateTitle');
  const gateErr = $('databaseGateError');
  gateErr.hidden = !gateError;
  gateErr.textContent = gateError;
  document.querySelectorAll<HTMLElement>('[data-db-name]').forEach((n) => {
    n.textContent = store.dbOpen ? store.settings.databaseName || store.settings.databasePath : t('dbCurrentNone');
  });
  document.querySelectorAll<HTMLElement>('[data-db-path]').forEach((n) => {
    n.textContent = store.dbOpen ? store.settings.databasePath : t('dbPathNone');
  });
  document.querySelectorAll<HTMLButtonElement>('[data-db-requires-open]').forEach((n) => {
    n.disabled = !store.dbOpen;
  });
}

export function openDbDialog(next: Mode, button?: HTMLElement | null): void {
  trigger = button || (document.activeElement as HTMLElement | null);
  mode = next;
  confirmMigration = false;
  chosenPath = next === 'relocate' ? store.settings.databasePath : '';
  const titles: Record<Mode, string> = {
    create: t('dbCreateTitle'), open: t('dbOpenTitle'), migrate: t('dbMigrateTitle'), relocate: t('dbRelocateTitle'),
  };
  const descs: Record<Mode, string> = {
    create: t('dbCreateDesc'), open: t('dbOpenDesc'), migrate: t('dbMigrateDesc'), relocate: t('dbRelocateDesc'),
  };
  $('databaseDialogTitle').textContent = titles[mode];
  $('databaseDialogDescription').textContent = descs[mode];
  $('databaseNameField').hidden = mode !== 'create';
  $<HTMLInputElement>('databaseName').value = t('dbNameDefault');
  $('databasePathLabel').textContent = mode === 'open' || mode === 'relocate' ? t('dbFileLabel') : t('dbFolderLabel');
  const pathInput = $<HTMLInputElement>('databasePath');
  pathInput.value = chosenPath;
  pathInput.readOnly = true;
  $('databaseChoose').textContent = mode === 'open' || mode === 'relocate' ? t('dbChooseBackup') : t('dbFolderChoose');
  if (mode === 'open' || mode === 'relocate') $('databaseChoose').textContent = t('dbFileLabel') + '…';
  $('databaseConfirm').hidden = true;
  $('databaseApply').textContent =
    mode === 'create' ? t('dbApplyCreate') : mode === 'migrate' ? t('dbApplyMigrate') : t('dbApplyOpen');
  clearError();
  dialog().showModal();
  (mode === 'create' ? $('databaseName') : $('databaseChoose')).focus();
}

async function choose(): Promise<void> {
  clearError();
  const path = mode === 'open' || mode === 'relocate'
    ? await store.host.pickFile(t('dbChooseBackup'), store.DB_FILTERS)
    : await store.host.pickFolder(t('dbChooseFolder'));
  if (path) {
    chosenPath = path;
    $<HTMLInputElement>('databasePath').value = path;
  }
}

async function apply(): Promise<void> {
  clearError();
  const name = ($('databaseName') as HTMLInputElement).value.trim();
  if (!chosenPath) { fail(t('dbErrNoPath')); return; }
  if (mode === 'create') {
    if (!name || /[\\/:*?"<>|]/.test(name)) { fail(t('dbErrBadName')); $('databaseName').focus(); return; }
    try {
      await store.createDb(chosenPath, name);
    } catch (e) { fail(t('dbErrCreateFailed', e instanceof Error ? e.message : String(e))); return; }
    dialog().close();
    announce(t('dbCreated', name));
    focusQuickAdd();
    return;
  }
  if (mode === 'open' || mode === 'relocate') {
    if (!/\.(sqlite|sqlite3|db)$/i.test(chosenPath)) { fail(t('dbErrBadExtension')); return; }
    try {
      await store.openDb(chosenPath);
    } catch (e) { fail(t('dbErrOpenFailed', e instanceof Error ? e.message : String(e))); return; }
    dialog().close();
    announce(mode === 'relocate' ? t('dbRelocated') : t('statusDatabaseConnected'));
    focusQuickAdd();
    return;
  }
  // migrate: two-step confirm; only switch on success.
  if (!confirmMigration) {
    confirmMigration = true;
    $('databaseFields').hidden = true;
    $('databaseConfirm').hidden = false;
    $('databaseConfirm').textContent = t('dbMigrateConfirmText', store.settings.databasePath, chosenPath + '/taskly.sqlite');
    $('databaseApply').textContent = t('dbConfirmMigrate');
    $('databaseCancel').focus();
    return;
  }
  try {
    await store.migrateDb(chosenPath);
  } catch (e) {
    $('databaseFields').hidden = false;
    $('databaseConfirm').hidden = true;
    confirmMigration = false;
    $('databaseApply').textContent = t('dbApplyMigrate');
    fail(t('dbErrMigrateFailed', e instanceof Error ? e.message : String(e)));
    return;
  }
  dialog().close();
  announce(t('dbMigrated'));
}

function focusQuickAdd(): void {
  const input = document.getElementById('quickAdd') as HTMLInputElement | null;
  if (input) input.focus();
}

export async function revealDatabase(): Promise<void> {
  const path = store.settings.databasePath;
  if (!path) return;
  const ok = await store.host.reveal(path);
  if (!ok) announce(t('revealUnavailable', path));
}

export function initDatabaseFlow(): void {
  document.addEventListener('click', (e) => {
    const button = (e.target as HTMLElement).closest<HTMLElement>('[data-db-action]');
    if (!button) return;
    const action = button.dataset.dbAction || '';
    if (action === 'reveal') { void revealDatabase(); return; }
    if (action === 'retry') {
      void store.openDb(store.settings.databasePath).then(() => {
        announce(t('statusDatabaseConnected'));
        focusQuickAdd();
      }).catch((err) => setGateMode('recovery', err instanceof Error ? err.message : String(err)));
      return;
    }
    if (action === 'create' || action === 'open' || action === 'migrate' || action === 'relocate') {
      openDbDialog(action, button);
    }
  });
  $('databaseChoose').addEventListener('click', () => { void choose(); });
  $('databaseCancel').addEventListener('click', () => dialog().close());
  $('databaseApply').addEventListener('click', () => { void apply(); });
  dialog().addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && (event.target as HTMLElement).tagName === 'INPUT') {
      event.preventDefault();
      void apply();
    }
  });
  dialog().addEventListener('close', () => {
    clearError();
    $('databaseFields').hidden = false;
    if (trigger && trigger.isConnected) trigger.focus();
  });
  store.onChange(refreshDatabaseUI);
  refreshDatabaseUI();
}

export { esc };