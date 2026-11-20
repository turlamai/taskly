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
//
// Waits are condition polls, not fixed sleeps: CI macOS VMs (especially
// Intel) round-trip RPCs slower than a dev box, and a fixed sleep turned
// that into false journey failures (slice 6).
import * as store from './store';
import * as rpc from '@taskly/core';
import { setGateMode, openDbDialog, refreshDatabaseUI } from './database-flow';

const $ = <T extends HTMLElement = HTMLElement>(s: string) => document.querySelector(s) as T | null;
const id = <T extends HTMLElement = HTMLElement>(s: string) => document.getElementById(s) as T | null;
const wait = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));
async function until(cond: () => boolean, label: string, ms = 6000): Promise<void> {
  const end = Date.now() + ms;
  while (!cond()) {
    if (Date.now() > end) throw new Error('timeout waiting for ' + label);
    await wait(60);
  }
}
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
  await until(() => (id<HTMLInputElement>('databasePath')?.value || '') === path, 'staged pick ' + path);
}

const row = (tid: number) => $('.row[data-id="' + tid + '"]');
const openEdit = (tid: number) => click(row(tid)?.querySelector('[data-act="edit"]') || null);
const openDetail = (tid: number) => click(row(tid)?.querySelector('[data-act="info"]') || null);
const closeDetail = () => click($('#dpop [data-act="close-detail"]'));
async function deleteViaDetail(tid: number): Promise<void> {
  openDetail(tid);
  await until(() => id('dpop')?.hidden === false, 'detail open for delete');
  click(id('fDelete')); // arm
  await wait(40);
  click(id('fDelete')); // confirm
  await until(() => !store.taskById(tid), 'staged delete hid row ' + tid);
}
async function quickAddViaUI(raw: string): Promise<number> {
  setInput(id<HTMLInputElement>('quickAdd'), raw);
  key(id('quickAdd'), 'Enter');
  await until(() => !!store.snapshot.tasks.find((x) => x.text === raw), 'quick add "' + raw + '"');
  return store.snapshot.tasks.find((x) => x.text === raw)!.id;
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
    t1 = await quickAddViaUI('alpha task');
    assert(t1 > 0, 'quick add via UI produced no task');
    click($('.lrow[data-list="' + listB + '"]'));
    await until(() => store.state.view === 'list' && store.state.listId === listB,
      'setup Beta list selected');
    t2 = await quickAddViaUI('beta needle');
    assert(t2 > 0, 'second list quick add failed');
    await until(() => store.taskById(t2)?.listId === listB,
      'setup beta task committed to the selected list');
    click($('[data-view="all"]'));
    await until(() => store.state.view === 'all' && store.state.listId === null,
      'setup All view selected');
    t3 = await quickAddViaUI('gamma doomed');
    assert(t3 > 0, 'third quick add failed');
  });

  await run('j01-quick-edit-escape', async () => {
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j01 editor open');
    setInput(id<HTMLInputElement>('etitle'), 'CHANGED-BY-DRAFT');
    key(id('etitle'), 'Escape');
    await until(() => !$('.row.editing'), 'j01 editor closed after Escape');
    assert(store.taskById(t1)?.text === 'alpha task', 'Escape leaked the draft');
  });

  await run('j02-quick-edit-return', async () => {
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j02 editor open');
    setInput(id<HTMLInputElement>('etitle'), 'alpha renamed');
    key(id('etitle'), 'Enter');
    await until(() => store.taskById(t1)?.text === 'alpha renamed', 'j02 Return commit');
    await store.refresh();
    assert(store.taskById(t1)?.text === 'alpha renamed', 'refresh lost the commit');
    // click-away commits the draft too (document pointerdown seam)
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j02 editor reopen');
    setInput(id<HTMLInputElement>('etitle'), 'alpha clicked');
    document.querySelector('.sidebar')?.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    await until(() => !$('.row.editing'), 'j02 click-away closed editor');
    await until(() => store.taskById(t1)?.text === 'alpha clicked', 'j02 click-away commit');
    await store.refresh();
    assert(store.taskById(t1)?.text === 'alpha clicked', 'refresh lost click-away commit');
  });

  await run('j03-quick-edit-save', async () => {
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j03 editor open');
    assert(!!id('etitle'), 'j03 etitle missing');
    assert(!!$('.enotes'), 'j03 enotes missing');
    setInput(id<HTMLInputElement>('etitle'), 'alpha saved');
    setInput($('.enotes') as HTMLTextAreaElement | null, 'note via save');
    click($('.row.editing [data-act="save"]'));
    await until(() => !$('.row.editing'), 'j03 Save closed editor');
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j03 editor reopen');
    assert(id<HTMLInputElement>('etitle')?.value === 'alpha saved', 'reopen lost title');
    assert(($('.enotes') as HTMLTextAreaElement | null)?.value === 'note via save', 'reopen lost notes');
    key(id('etitle'), 'Escape');
    await until(() => !$('.row.editing'), 'j03 escape closed reopen');
  });

  await run('j04-quick-edit-save-failure', async () => {
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j04 editor open');
    setInput(id<HTMLInputElement>('etitle'), 'x'.repeat(1001));
    click($('.row.editing [data-act="save"]'));
    await until(() => live().length > 0, 'j04 failure announced');
    assert($('.row.editing') != null, 'draft discarded on save failure');
    assert(id<HTMLInputElement>('etitle')?.value.length === 1001, 'draft fields lost');
    assert(store.taskById(t1)?.text === 'alpha saved', 'stored record mutated on failure');
    setInput(id<HTMLInputElement>('etitle'), 'alpha saved');
    key(id('etitle'), 'Escape');
    await until(() => !$('.row.editing'), 'j04 escape closed editor');
  });

  await run('j05-quick-edit-cancel', async () => {
    openEdit(t1);
    await until(() => !!$('.row.editing'), 'j05 editor open');
    setInput(id<HTMLInputElement>('etitle'), 'DISCARD-ME');
    click($('.row.editing [data-act="cancel"]'));
    await until(() => !$('.row.editing'), 'j05 Cancel closed editor');
    assert(store.taskById(t1)?.text === 'alpha saved', 'Cancel committed the draft');
  });

  await run('j06-detail-field-change', async () => {
    openDetail(t1);
    await until(() => id('dpop')?.hidden === false, 'j06 detail open');
    change(id<HTMLTextAreaElement>('fNote'), 'detail note');
    await until(() => store.taskById(t1)?.notes === 'detail note', 'j06 notes autosave');
    await store.refresh();
    assert(store.taskById(t1)?.notes === 'detail note', 'refresh lost autosave');
    closeDetail();
    await until(() => id('dpop')?.hidden === true, 'j06 detail closed');
    openDetail(t1);
    await until(() => id('dpop')?.hidden === false, 'j06 detail reopen');
    assert(id<HTMLTextAreaElement>('fNote')?.value === 'detail note', 'reopen lost notes');
  });

  await run('j07-detail-persist-failure', async () => {
    change(id<HTMLInputElement>('fDate'), 'garbage-date');
    await until(() => live().length > 0, 'j07 anchored error announced');
    assert(id('dpop')?.hidden === false, 'popover closed on persist failure');
    assert(!store.taskById(t1)?.dueDate, 'invalid date persisted');
    assert(id<HTMLTextAreaElement>('fNote')?.value === 'detail note', 'other field disturbed');
    change(id<HTMLInputElement>('fDate'), '');
    await until(() => live().length === 0 || !store.taskById(t1)?.dueDate, 'j07 date cleared');
    closeDetail();
    await until(() => id('dpop')?.hidden === true, 'j07 detail closed');
  });

  await run('j08-detail-close-persisted', async () => {
    openDetail(t1);
    await until(() => id('dpop')?.hidden === false, 'j08 detail open');
    click($('#fPrio [data-prio="2"]'));
    await until(() => store.taskById(t1)?.priority === 2, 'j08 priority autosave');
    closeDetail();
    await until(() => id('dpop')?.hidden === true, 'j08 detail closed');
    assert(store.taskById(t1)?.priority === 2, 'priority not persisted before close');
    openDetail(t1);
    await until(() => id('dpop')?.hidden === false, 'j08 detail reopen');
    assert($('#fPrio [data-prio="2"]')?.getAttribute('aria-pressed') === 'true', 'reopen lost priority');
    closeDetail();
    await until(() => id('dpop')?.hidden === true, 'j08 detail closed again');
  });

  await run('j09-delete-undo', async () => {
    await deleteViaDetail(t1);
    assert(!store.taskById(t1), 'delete did not hide the row');
    assert(id('undoBanner')?.hidden === false, 'undo banner missing');
    click(id('undoBtn'));
    await until(() => !!store.taskById(t1), 'j09 undo restored');
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
    await until(() => store.state.q === 'needle', 'j11 search owner');
    // Poll the final observable (owner text), not a proxy: on slow macOS
    // VMs the row node can exist a tick before its meta text settles.
    try {
      await until(() => store.visible().some((x) => x.id === t2) &&
        (row(t2)?.querySelector('.owner')?.textContent || '').includes('Beta'),
        'j11 owner label rendered');
    } catch {
      throw new Error('owner label lost: row=' + (row(t2)?.outerHTML || 'none').slice(0, 300) +
        ' lists=' + JSON.stringify(store.snapshot.lists.map((l) => [l.id, l.name])) +
        ' q=' + store.state.q);
    }
    await rpc.addTask('needle two', listB, null, null, null);
    // engine `changed` → store refresh (push or SSE fallback)
    await until(() => store.visible().some((x) => x.text === 'needle two'),
      'j11 changed event reflected: events=' + store.changedEvents, 9000);
    assert(store.state.q === 'needle', 'refresh stole search ownership');
    setInput(id<HTMLInputElement>('q'), '');
    await until(() => store.state.q === '', 'j11 search cleared');
  });

  await run('j12-database-switch', async () => {
    openDetail(t1);
    await until(() => id('dpop')?.hidden === false, 'j12 detail open');
    await store.createDb(home + '/dbB', 'e2eB');
    await until(() => store.dbOpen, 'j12 switch opened B');
    assert(store.state.q === '' && store.state.listId === null, 'view state not cleared');
    assert(id('dpop')?.hidden === true, 'detail popover survived switch');
    assert(id('undoBanner')?.hidden === true, 'undo state survived switch');
    await store.openDb(dbA);
    await until(() => !!store.taskById(t1), 'j12 A tasks after switch back');
  });

  await run('j13-gate-create-collision', async () => {
    await store.closeDb();
    await until(() => id('databaseGate')?.hidden === false, 'j13 gate shown after close');
    openDbDialog('create');
    await wait(60);
    await stagePick(home + '/dbA');
    setInput(id<HTMLInputElement>('databaseName'), 'e2eA');
    click(id('databaseApply'));
    await until(() => id('databaseError')?.hidden === false, 'j13 collision error surfaced');
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
    await until(() => store.dbOpen, 'j13 gate create opened');
    assert(store.snapshot.lists.length > 0, 'created database lacks default list');
    assert(id<HTMLDialogElement>('databaseDialog')?.open === false, 'create dialog stayed open');
    const reboot = await store.boot();
    assert(reboot.mode === 'ok', 'relaunch did not reopen the created database');
    await store.openDb(dbA);
    await until(() => !!store.taskById(t1), 'j13 back on A');
  });

  await run('j14-recovery-missing-retry-relocate', async () => {
    await store.openDb(dbA);
    await until(() => !!store.taskById(t1), 'j14 open A');
    await store.migrateDb(home + '/copy'); // source left in place
    await until(() => (store.settings.databasePath || '').replace(/\\/g, '/').includes('/copy/'), 'j14 migrate recorded copy');
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
    await until(() => store.dbOpen && !!store.taskById(t1), 'j14 retry reopened restored db');
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
    await until(() => store.dbOpen, 'j14 relocate open', 6000).catch(() => undefined);
    assert(store.dbOpen, 'relocate did not open; err=' + (id('databaseError')?.textContent || '') +
      ' path=' + (id<HTMLInputElement>('databasePath')?.value || '') +
      ' dlgOpen=' + String(id<HTMLDialogElement>('databaseDialog')?.open));
    assert(!!store.taskById(t1), 'relocate lost tasks');
    assert(id<HTMLDialogElement>('databaseDialog')?.open === false, 'relocate dialog stayed open');
  });

  await run('j15-migrate-success-collision-failure', async () => {
    const n = store.snapshot.tasks.length;
    await store.migrateDb(home + '/mig');
    await until(() => (store.settings.databasePath || '').replace(/\\/g, '/').includes('/mig/'), 'j15 migrate recorded');
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
    await until(() => store.snapshot.tasks.some((x) => x.text === 'changed since preview'),
      'j16 changed push bumped generation', 9000);
    let threw = false;
    try { await store.restoreBackup(bp); } catch { threw = true; }
    assert(threw, 'stale-preview restore not refused');
    await store.previewBackup(bp);
    await store.restoreBackup(bp);
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
    const tid = await quickAddViaUI('default list target');
    const t = store.taskById(tid);
    assert(!!t && t.listId === beta!.id, 'quick add ignored the default list');
    await store.setSetting('default-list-id', '0');
  });

  await report('done', true, '');
}