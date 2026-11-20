// In-page acceptance harness (issue #141 slice 5). glaze exposes no JS
// injection into the webview, so the PRODUCT-SPEC §6 lifecycle journeys run
// INSIDE the real window: real DOM events → the production handlers →
// store → typed RPC → unchanged engine. Inert unless BOTH the URL hash is
// #e2e AND the host gate (TASKLY_E2E=1) answers enabled=true; results are
// posted to api/host/e2e_report and collected by verify.rkt.
//
// Native OS dialogs (folder/file pickers) cannot be clicked headlessly;
// journeys feed the same store APIs the dialog's apply() calls, with the
// dialog's own error surface asserted where the flow owns one (§6 gate
// collision). Declared in the issue backfill.
import * as store from './store';
import * as rpc from '@taskly/core';
import { setGateMode, openDbDialog, refreshDatabaseUI } from './database-flow';

const $ = <T extends HTMLElement = HTMLElement>(s: string) => document.querySelector(s) as T | null;
const id = <T extends HTMLElement = HTMLElement>(s: string) => document.getElementById(s) as T | null;
const wait = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));
const click = (el: Element | null) => el?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
const key = (el: Element | null, k: string) => el?.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }));
function setInput(el: HTMLInputElement | HTMLTextAreaElement | null, v: string): void {
  if (!el) throw new Error('missing input');
  el.value = v;
  el.dispatchEvent(new Event('input', { bubbles: true }));
}
function change(el: HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | null, v: string): void {
  if (!el) throw new Error('missing field');
  el.value = v;
  el.dispatchEvent(new Event('change', { bubbles: true }));
}
const live = () => (id('live')?.textContent || '').trim();
function assert(ok: boolean, msg: string): void { if (!ok) throw new Error(msg); }
// Native pickers cannot be clicked headlessly: stage the path the OS modal
// would return, then drive the dialog's own Choose button (declared gap).
async function stagePick(path: string): Promise<void> {
  await store.host.e2eFs('stage_pick', path);
  click(id('databaseChoose'));
  await wait(150);
}

const row = (tid: number) => $('.row[data-id="' + tid + '"]');
const openEdit = (tid: number) => click(row(tid)?.querySelector('[data-act="edit"]') || null);
const openDetail = (tid: number) => click(row(tid)?.querySelector('[data-act="info"]') || null);
const closeDetail = () => click($('#dpop [data-act="close-detail"]'));
async function deleteViaDetail(tid: number): Promise<void> {
  openDetail(tid);
  await wait(60);
  click(id('fDelete')); // arm
  await wait(40);
  click(id('fDelete')); // confirm
  await wait(160);
}
async function quickAddViaUI(raw: string): Promise<void> {
  setInput(id<HTMLInputElement>('quickAdd'), raw);
  key(id('quickAdd'), 'Enter');
  await wait(200);
}

export async function bootE2E(): Promise<void> {
  let ctx: { enabled: boolean; home: string };
  try {
    ctx = await store.host.e2e();
  } catch {
    return; // gate closed: production page, harness stays inert
  }
  if (!ctx.enabled) return;
  const home = ctx.home;
  const report = (jid: string, ok: boolean, detail: string) =>
    store.host.e2eReport(jid, ok, detail).catch(() => undefined);
  const run = async (jid: string, fn: () => Promise<void>) => {
    try {
      await fn();
      await report(jid, true, '');
    } catch (e) {
      await report(jid, false, e instanceof Error ? e.message : String(e));
    }
  };

  const dbA = home + '/dbA/taskly.sqlite';
  const dbB = home + '/dbB/taskly.sqlite';
  let t1 = 0; let t2 = 0; let t3 = 0; let listB = 0;

  await run('setup', async () => {
    await store.createDb(home + '/dbA', 'e2eA');
    assert(store.dbOpen, 'createDb did not open');
    const l = await store.createList('Beta', '📚', -16745729);
    listB = l.id;
    await quickAddViaUI('alpha task');
    t1 = store.snapshot.tasks.find((x) => x.text === 'alpha task')?.id || 0;
    assert(t1 > 0, 'quick add via UI produced no task');
    click($('.lrow[data-list="' + listB + '"]'));
    await wait(60);
    await quickAddViaUI('beta needle');
    t2 = store.snapshot.tasks.find((x) => x.text === 'beta needle')?.id || 0;
    assert(t2 > 0, 'second list quick add failed');
    click($('[data-view="all"]'));
    await wait(60);
    await quickAddViaUI('gamma doomed');
    t3 = store.snapshot.tasks.find((x) => x.text === 'gamma doomed')?.id || 0;
    assert(t3 > 0, 'third quick add failed');
  });

  await run('j01-quick-edit-escape', async () => {
    openEdit(t1);
    await wait(60);
    setInput(id<HTMLInputElement>('etitle'), 'CHANGED-BY-DRAFT');
    key(id('etitle'), 'Escape');
    await wait(120);
    assert(!$('.row.editing'), 'editor still open after Escape');
    assert(store.taskById(t1)?.text === 'alpha task', 'Escape leaked the draft');
  });

  await run('j02-quick-edit-return', async () => {
    openEdit(t1);
    await wait(60);
    setInput(id<HTMLInputElement>('etitle'), 'alpha renamed');
    key(id('etitle'), 'Enter');
    await wait(200);
    assert(store.taskById(t1)?.text === 'alpha renamed', 'Return did not commit');
    await store.refresh();
    assert(store.taskById(t1)?.text === 'alpha renamed', 'refresh lost the commit');
    // click-away commits the draft too (document pointerdown seam)
    openEdit(t1);
    await wait(60);
    setInput(id<HTMLInputElement>('etitle'), 'alpha clicked');
    document.querySelector('.sidebar')?.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    await wait(220);
    assert(!$('.row.editing'), 'click-away left the editor open');
    assert(store.taskById(t1)?.text === 'alpha clicked', 'click-away did not commit');
    await store.refresh();
    assert(store.taskById(t1)?.text === 'alpha clicked', 'refresh lost click-away commit');
  });

  await run('j03-quick-edit-save', async () => {
    openEdit(t1);
    await wait(60);
    assert(!!$('.row.editing'), 'j03 editor not open');
    assert(!!id('etitle'), 'j03 etitle missing');
    assert(!!$('.enotes'), 'j03 enotes missing');
    setInput(id<HTMLInputElement>('etitle'), 'alpha saved');
    setInput($('.enotes') as HTMLTextAreaElement | null, 'note via save');
    click($('.row.editing [data-act="save"]'));
    await wait(220);
    assert(!$('.row.editing'), 'Save left the editor open');
    openEdit(t1);
    await wait(60);
    assert(id<HTMLInputElement>('etitle')?.value === 'alpha saved', 'reopen lost title');
    assert(($('.enotes') as HTMLTextAreaElement | null)?.value === 'note via save', 'reopen lost notes');
    key(id('etitle'), 'Escape');
    await wait(100);
  });

  await run('j04-quick-edit-save-failure', async () => {
    openEdit(t1);
    await wait(60);
    setInput(id<HTMLInputElement>('etitle'), 'x'.repeat(1001));
    click($('.row.editing [data-act="save"]'));
    await wait(260);
    assert(live().length > 0, 'no actionable error announced');
    assert($('.row.editing') != null, 'draft discarded on save failure');
    assert(id<HTMLInputElement>('etitle')?.value.length === 1001, 'draft fields lost');
    assert(store.taskById(t1)?.text === 'alpha saved', 'stored record mutated on failure');
    setInput(id<HTMLInputElement>('etitle'), 'alpha saved');
    key(id('etitle'), 'Escape');
    await wait(100);
  });

  await run('j05-quick-edit-cancel', async () => {
    openEdit(t1);
    await wait(60);
    setInput(id<HTMLInputElement>('etitle'), 'DISCARD-ME');
    click($('.row.editing [data-act="cancel"]'));
    await wait(120);
    assert(!$('.row.editing'), 'Cancel left the editor open');
    assert(store.taskById(t1)?.text === 'alpha saved', 'Cancel committed the draft');
  });

  await run('j06-detail-field-change', async () => {
    openDetail(t1);
    await wait(80);
    change(id<HTMLTextAreaElement>('fNote'), 'detail note');
    await wait(220);
    assert(store.taskById(t1)?.notes === 'detail note', 'notes autosave failed');
    await store.refresh();
    assert(store.taskById(t1)?.notes === 'detail note', 'refresh lost autosave');
    closeDetail();
    await wait(60);
    assert(id('dpop')?.hidden === true, 'detail did not close');
    openDetail(t1);
    await wait(80);
    assert(id<HTMLTextAreaElement>('fNote')?.value === 'detail note', 'reopen lost notes');
  });

  await run('j07-detail-persist-failure', async () => {
    change(id<HTMLInputElement>('fDate'), 'garbage-date');
    await wait(260);
    assert(live().length > 0, 'no anchored error announced');
    assert(id('dpop')?.hidden === false, 'popover closed on persist failure');
    assert(!store.taskById(t1)?.dueDate, 'invalid date persisted');
    assert(id<HTMLTextAreaElement>('fNote')?.value === 'detail note', 'other field disturbed');
    change(id<HTMLInputElement>('fDate'), '');
    await wait(200);
    closeDetail();
    await wait(60);
  });

  await run('j08-detail-close-persisted', async () => {
    openDetail(t1);
    await wait(80);
    click($('#fPrio [data-prio="2"]'));
    await wait(220);
    closeDetail();
    await wait(60);
    assert(store.taskById(t1)?.priority === 2, 'priority not persisted before close');
    openDetail(t1);
    await wait(80);
    assert($('#fPrio [data-prio="2"]')?.getAttribute('aria-pressed') === 'true', 'reopen lost priority');
    closeDetail();
    await wait(60);
  });

  await run('j09-delete-undo', async () => {
    await deleteViaDetail(t1);
    assert(!store.taskById(t1), 'delete did not hide the row');
    assert(id('undoBanner')?.hidden === false, 'undo banner missing');
    click(id('undoBtn'));
    await wait(220);
    const back = store.taskById(t1);
    assert(!!back, 'undo did not restore');
    assert(back?.notes === 'detail note' && back?.priority === 2, 'undo lost metadata');
    assert(id('undoBanner')?.hidden === true, 'undo banner stayed');
  });

  await run('j10-delete-timeout', async () => {
    await deleteViaDetail(t3);
    assert(!store.taskById(t3), 'delete did not hide the row');
    await wait(6500);
    await store.refresh();
    assert(!store.taskById(t3), 'expired delete came back');
  });

  await run('j11-search-refresh', async () => {
    setInput(id<HTMLInputElement>('q'), 'needle');
    await wait(400);
    assert(store.state.q === 'needle', 'search not owner');
    assert(store.visible().some((x) => x.id === t2), 'search misses other-list task');
    assert((row(t2)?.querySelector('.owner')?.textContent || '').includes('Beta'), 'owner label lost');
    await rpc.addTask('needle two', listB, null, null, null);
    await wait(600); // engine `changed` → store refresh
    assert(store.state.q === 'needle', 'refresh stole search ownership');
    assert(store.visible().some((x) => x.text === 'needle two'),
      'changed event not reflected: events=' + store.changedEvents +
      ' results=' + JSON.stringify((store.searchResults || []).map((x) => x.text)));
    setInput(id<HTMLInputElement>('q'), '');
    await wait(300);
  });

  await run('j12-database-switch', async () => {
    openDetail(t1);
    await wait(60);
    await store.createDb(home + '/dbB', 'e2eB');
    await wait(120);
    assert(store.dbOpen, 'switch did not open B');
    assert(store.state.q === '' && store.state.listId === null, 'view state not cleared');
    assert(id('dpop')?.hidden === true, 'detail popover survived switch');
    assert(id('undoBanner')?.hidden === true, 'undo state survived switch');
    await store.openDb(dbA);
    await wait(120);
    assert(!!store.taskById(t1), 'A tasks missing after switch back');
  });

  await run('j13-gate-create-collision', async () => {
    await store.closeDb();
    await wait(100);
    assert(id('databaseGate')?.hidden === false, 'gate not shown after close');
    openDbDialog('create');
    await wait(60);
    await stagePick(home + '/dbA');
    setInput(id<HTMLInputElement>('databaseName'), 'e2eA');
    click(id('databaseApply'));
    await wait(260);
    assert(id('databaseError')?.hidden === false, 'collision error not surfaced');
    assert(id<HTMLDialogElement>('databaseDialog')?.open === true, 'dialog closed on collision');
    assert(!store.dbOpen, 'collision opened a database');
    click(id('databaseCancel'));
    await wait(60);
    // gate → create success: empty folder + name opens and is recorded
    openDbDialog('create');
    await wait(60);
    await stagePick(home + '/dbC');
    setInput(id<HTMLInputElement>('databaseName'), 'e2eC');
    click(id('databaseApply'));
    await wait(300);
    assert(store.dbOpen, 'gate create did not open');
    assert(store.snapshot.lists.length > 0, 'created database lacks default list');
    assert(id<HTMLDialogElement>('databaseDialog')?.open === false, 'create dialog stayed open');
    const reboot = await store.boot();
    assert(reboot.mode === 'ok', 'relaunch did not reopen the created database');
    await store.openDb(dbA);
    await wait(120);
  });

  await run('j14-recovery-missing-retry-relocate', async () => {
    await store.openDb(dbA);
    await wait(120);
    await store.migrateDb(home + '/copy'); // source left in place
    await wait(160);
    const copy = home + '/copy/taskly.sqlite'; // now the recorded path
    // Windows keeps an open SQLite handle: close before unlinking.
    await store.closeDb();
    await wait(80);
    await store.host.e2eFs('unlink', copy);
    const boot1 = await store.boot();
    setGateMode(boot1.mode === 'ok' ? 'gate' : boot1.mode, boot1.mode === 'ok' ? '' : boot1.error);
    refreshDatabaseUI();
    await wait(80);
    assert(boot1.mode === 'recovery', 'boot1 mode=' + boot1.mode + ' err=' + (boot1.mode === 'ok' ? '' : boot1.error));
    assert(id('databaseRecovery')?.hidden === false, 'recovery block hidden');
    assert((id('databaseMissingPath')?.textContent || '').includes('copy'), 'recorded path not shown');
    // retry after the recorded file is restored in place (source copy)
    await store.host.e2eFs('copy', dbA, copy);
    click($('[data-db-action="retry"]'));
    await wait(300);
    assert(store.dbOpen, 'retry did not reopen the restored database');
    assert(!!store.taskById(t1), 'retry lost tasks');
    // relocate to the untouched source while the recorded path is missing
    await store.closeDb();
    await wait(80);
    await store.host.e2eFs('unlink', copy);
    const boot2 = await store.boot();
    setGateMode(boot2.mode === 'ok' ? 'gate' : boot2.mode, boot2.mode === 'ok' ? '' : boot2.error);
    refreshDatabaseUI();
    await wait(80);
    assert(boot2.mode === 'recovery', 'second missing file did not enter recovery');
    openDbDialog('relocate');
    await wait(60);
    await stagePick(dbA);
    click(id('databaseApply'));
    await wait(300);
    assert(store.dbOpen, 'relocate did not open');
    assert(!!store.taskById(t1), 'relocate lost tasks');
    assert(id<HTMLDialogElement>('databaseDialog')?.open === false, 'relocate dialog stayed open');
  });

  await run('j15-migrate-success-collision-failure', async () => {
    const n = store.snapshot.tasks.length;
    await store.migrateDb(home + '/mig');
    await wait(200);
    assert(store.snapshot.tasks.length === n, 'migrate lost tasks');
    assert((await store.host.e2eFs('exists', dbA)).exists, 'source removed by migrate');
    let threw = false;
    try { await store.migrateDb(home + '/mig'); } catch { threw = true; }
    assert(threw, 'migrate collision not rejected');
    await store.host.e2eFs('write', home + '/occupied/taskly.sqlite', 'not a database');
    threw = false;
    try { await store.migrateDb(home + '/occupied'); } catch { threw = true; }
    assert(threw, 'migrate onto a file not rejected');
    assert(store.dbOpen && store.snapshot.tasks.length === n, 'failed migrate disturbed the open db');
  });

  await run('j16-backup-export-restore-refused', async () => {
    const bp = home + '/backup.json';
    const count = await store.exportBackup(bp);
    assert(count > 0, 'export reported no tasks');
    const prev = await store.previewBackup(bp);
    assert(prev.taskCount === count, 'preview counts differ from export');
    await rpc.addTask('changed since preview', null, null, null, null);
    await wait(200);
    let threw = false;
    try { await store.restoreBackup(bp); } catch { threw = true; }
    assert(threw, 'stale-preview restore not refused');
    await store.previewBackup(bp);
    await store.restoreBackup(bp);
    await wait(200);
    await store.refresh();
    assert(!store.snapshot.tasks.some((x) => x.text === 'changed since preview'), 'restore did not replace');
    // restore replaces rows in one transaction; identities are re-minted
    // by the engine (DATA-FORMAT §9), so assert content, not old ids.
    assert(store.snapshot.tasks.some((x) => x.text === 'alpha saved'), 'restore lost original tasks');
    assert(store.snapshot.tasks.length === prev.taskCount, 'restore count differs from preview');
    const bad = home + '/bad.json';
    await store.host.e2eFs('write', bad, '{not a backup');
    threw = false;
    try { await store.previewBackup(bad); } catch { threw = true; }
    assert(threw, 'invalid backup not refused');
  });

  await run('j17-new-task-default-list', async () => {
    const beta = store.snapshot.lists.find((l) => l.name === 'Beta');
    assert(!!beta, 'Beta list missing after restore');
    await store.setSetting('default-list-id', String(beta!.id));
    await quickAddViaUI('default list target');
    const t = store.snapshot.tasks.find((x) => x.text === 'default list target');
    assert(!!t && t.listId === beta!.id, 'quick add ignored the default list');
    await store.setSetting('default-list-id', '0');
  });

  await report('done', true, '');
}