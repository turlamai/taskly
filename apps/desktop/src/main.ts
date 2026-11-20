// Taskly single web UI — main window, ported from design/prototype/
// main-window.html (the visual source) onto the engine data layer.
// Rendering/event structure follows the prototype; every mutation is a
// typed RPC followed by a snapshot refetch (store.ts).
import { t, setLang, resolveLang, getLang } from './i18n';
import * as store from './store';
import type { Task } from '@taskly/core';
import {
  ICONS, esc, addDays, fmtDate, bucket, dueText, place, announce,
  prepareDetails, fillIcons, listColorStyle, TODAY,
} from './shared';
import { initTheme, applyTheme } from './theme';
import { initDatabaseFlow, setGateMode, refreshDatabaseUI } from './database-flow';
import { initListEditor, openListEditor } from './list-editor';
import { initSettings, openSettings } from './settings';

const $ = <T extends HTMLElement = HTMLElement>(s: string, r?: ParentNode) => (r || document).querySelector(s) as T | null;
const $$ = <T extends HTMLElement = HTMLElement>(s: string, r?: ParentNode) => Array.from((r || document).querySelectorAll(s)) as T[];

let editing: number | null = null;
let draft: { text: string; dueDate: string; dueTime: string; priority: number; notes: string } | null = null;
let openId: number | null = null;
let delArmed = false;
let undoTask: Task | null = null;
let undoTimer = 0;
let searchTimer = 0;

const PRIO_KEYS = ['prioNone', 'prioLow', 'prioMedium', 'prioHigh'];

/* ---- static i18n labels ---- */
function applyStaticI18n(): void {
  $$('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n || ''); });
  $$('[data-i18n-placeholder]').forEach((el) => { (el as HTMLInputElement).placeholder = t(el.dataset.i18nPlaceholder || ''); });
  $$('[data-i18n-aria]').forEach((el) => { el.setAttribute('aria-label', t(el.dataset.i18nAria || '')); });
}

/* ---- sidebar ---- */
function renderSidebar(): void {
  const c = store.snapshot.counts;
  const tiles = [
    { view: 'today', label: t('navToday'), count: c.today, glyph: '<span class="glyph num">' + ICONS.today + '</span>' },
    { view: 'planned', label: t('navPlanned'), count: c.planned, glyph: '<span class="glyph planned">' + ICONS.calendar + '</span>' },
    { view: 'all', label: t('navAll'), count: c.all, glyph: '<span class="glyph gray">' + ICONS.lines + '</span>' },
    { view: 'completed', label: t('navCompleted'), count: c.completed, glyph: '<span class="glyph gray">' + ICONS.checkCircle + '</span>' },
  ];
  $('#tiles')!.innerHTML = tiles.map((x) =>
    '<button class="tile" data-view="' + x.view + '" aria-current="' + (store.state.view === x.view) + '">' +
    x.glyph.replace('class="icon"', 'class="icon tile-icon"') + '<span class="label">' + esc(x.label) + '</span><span class="count">' + x.count + '</span></button>').join('');

  $('#lists')!.innerHTML = store.snapshot.lists.map((l) => {
    const on = store.state.view === 'list' && store.state.listId === l.id;
    return '<button class="lrow" data-list="' + l.id + '" aria-current="' + on + '">' +
      '<span class="ldot" style="background:' + listColorStyle(l.color) + '">' + esc(l.icon || '📋') + '</span>' +
      '<span class="name">' + esc(l.name) + '</span><span class="count">' + l.pendingCount + '</span></button>';
  }).join('');

  const tags = store.tagCounts();
  $('#tags')!.innerHTML = tags.size ? Array.from(tags.entries()).map(([g, n]) =>
    '<button class="trow" data-tag="' + esc(g) + '" aria-pressed="' + (store.state.tag === g) + '">' +
    '<span class="thash">#</span><span class="name">' + esc(g) + '</span><span class="count">' + n + '</span></button>').join('')
    : '<div class="thint">' + esc(t('tagsHint')) + '</div>';
}

/* ---- header ---- */
function viewMeta(): { title: string; sub: string; openN: number; total: number } {
  const all = store.visible();
  const openN = all.filter((x) => !x.completed).length;
  let title: string; let sub: string;
  if (store.state.view === 'list') {
    title = store.listById(store.state.listId)?.name || t('navAll');
    sub = t('subtitleOpenTasks', openN);
  } else if (store.state.view === 'today') {
    const [y = 1970, mo = 1, d = 1] = TODAY.split('-').map(Number);
    const date = new Date(y, mo - 1, d);
    const weekday = new Intl.DateTimeFormat(getLang() === 'zh' ? 'zh-CN' : 'en-US', { weekday: 'long' }).format(date);
    title = t('navToday');
    sub = t('subtitleToday', y, mo, d, weekday);
  } else if (store.state.view === 'planned') { title = t('navPlanned'); sub = t('subtitleOpenTasks', openN); }
  else if (store.state.view === 'all') { title = t('navAll'); sub = t('subtitleOpenTasks', openN); }
  else { title = t('navCompleted'); sub = t('subtitleCompleted', all.length); }
  if (store.state.tag) sub = t('subtitleTagFilter', store.state.tag, openN);
  else if (store.state.q) sub = t('subtitleSearch', store.state.q, all.length);
  return { title, sub, openN, total: all.length };
}

function renderHeader(): void {
  const m = viewMeta();
  $('#vTitle')!.textContent = m.title;
  $('#vSub')!.textContent = m.sub;
  const editBtn = $('#editListBtn');
  if (editBtn) editBtn.hidden = store.state.view !== 'list';
  const fb = $('#filterBar')!;
  if (store.state.tag || store.state.q) {
    fb.hidden = false;
    fb.innerHTML = '<span>' + esc(t('filterPrefix')) + (store.state.tag ? '#' + esc(store.state.tag) : '') +
      (store.state.tag && store.state.q ? ' · ' : '') +
      (store.state.q ? '“' + esc(store.state.q) + '”' : '') + '</span><span class="sp"></span>' +
      '<button class="btn ghost" data-act="clear-filter">' + esc(t('dialogClear')) + '</button>';
  } else fb.hidden = true;
}

/* ---- rows ---- */
function dateChip(d: { dueDate: string; dueTime: string }): string {
  if (!d.dueDate) return t('noDate');
  const time = d.dueTime ? ' ' + d.dueTime : '';
  if (d.dueDate === TODAY) return t('navToday') + time;
  if (d.dueDate === addDays(TODAY, 1)) return t('dateTomorrow') + time;
  return fmtDate(d.dueDate) + time;
}

function rowMeta(task: Task): string {
  const parts: string[] = [];
  const due = dueText(task);
  const b = bucket(task);
  if (due) parts.push('<span class="due ' + (b === 'over' ? 'over' : b === 'today' ? 'today' : '') + '">' + esc(due) + '</span>');
  if (task.priority > 0) parts.push('<span class="prio p' + task.priority + '" aria-label="' + esc(t('fieldPriority')) + ': ' + esc(t(PRIO_KEYS[task.priority] ?? 'prioNone')) + '">' + '!'.repeat(task.priority) + '</span>');
  const l = store.listById(task.listId);
  if (l) parts.push('<span class="owner"><i style="background:' + listColorStyle(l.color) + '"></i>' + esc(l.name) + '</span>');
  for (const g of task.tags) parts.push('<button class="tag" data-act="tag" data-tag="' + esc(g) + '">#' + esc(g) + '</button>');
  if (task.subtasks.length) {
    const done = task.subtasks.filter((s) => s.done).length;
    parts.push('<span class="subcount">' + esc(t('subtitleSubtaskCount', done, task.subtasks.length)) + '</span>');
  }
  if (task.notes) parts.push('<span class="note">' + esc(task.notes) + '</span>');
  return '<div class="meta">' + parts.join('') + '</div>';
}

function rowHTML(task: Task): string {
  if (editing === task.id) return editorHTML(task);
  const l = store.listById(task.listId);
  const color = l ? listColorStyle(l.color) : 'var(--accent)';
  return '<div class="row' + (openId === task.id ? ' sel' : '') + '" data-id="' + task.id + '">' +
    '<button class="check' + (task.completed ? ' done' : '') + '" data-act="toggle" role="checkbox" aria-checked="' + task.completed + '"' +
    ' aria-label="' + esc(t('menuToggleCompleted')) + ': ' + esc(task.text) + '" style="--list:' + color + '">' + (task.completed ? ICONS.check : '') + '</button>' +
    '<div class="body"><button class="t' + (task.completed ? ' done' : '') + '" data-act="edit">' + esc(task.text) + '</button>' + rowMeta(task) + '</div>' +
    '<button class="info" data-act="info" aria-label="' + esc(t('dialogTaskDetail')) + ': ' + esc(task.text) + '" aria-haspopup="dialog" aria-expanded="' + (openId === task.id) + '">' + ICONS.info + '</button></div>';
}

function editorHTML(task: Task): string {
  const l = store.listById(task.listId);
  const color = l ? listColorStyle(l.color) : 'var(--accent)';
  const d = draft!;
  return '<div class="row editing' + (openId === task.id ? ' sel' : '') + '" data-id="' + task.id + '">' +
    '<button class="check" data-act="toggle" role="checkbox" aria-checked="' + task.completed + '" aria-label="' + esc(t('menuToggleCompleted')) + ': ' + esc(task.text) + '" style="--list:' + color + '">' + (task.completed ? ICONS.check : '') + '</button>' +
    '<div class="body"><div class="editor">' +
    '<input class="etitle" id="etitle" type="text" value="' + esc(d.text) + '" aria-label="' + esc(t('fieldTitle')) + '" autocomplete="off">' +
    '<div class="echips">' +
    '<button class="echip" id="chipDate" data-act="cycle-date">' + ICONS.calendar + '<span>' + esc(dateChip(d)) + '</span></button>' +
    '<button class="echip" id="chipPrio" data-act="cycle-prio">' + ICONS.flag + '<span>' + esc(t('editorPrioChip', t(PRIO_KEYS[d.priority] ?? 'prioNone'))) + '</span></button>' +
    '</div>' +
    '<textarea class="enotes" rows="2" aria-label="' + esc(t('fieldNotes')) + '" placeholder="' + esc(t('notesPlaceholder')) + '">' + esc(d.notes) + '</textarea>' +
    '<div class="eacts"><button class="btn primary" data-act="save">' + esc(t('dialogSave')) + '</button>' +
    '<button class="btn" data-act="cancel">' + esc(t('dialogCancel')) + '</button>' +
    '<span class="hint">' + esc(t('editorHint')) + '</span></div>' +
    '</div></div>' +
    '<button class="info" data-act="info" aria-label="' + esc(t('dialogTaskDetail')) + ': ' + esc(task.text) + '" aria-haspopup="dialog" aria-expanded="false">' + ICONS.info + '</button></div>';
}

function emptyHTML(): string {
  if (store.state.tag || store.state.q) {
    return '<div class="empty"><div class="et">' + esc(t('emptySearchTitle')) + '</div>' +
      '<div class="es">' + esc(t('emptySearchBody')) + '</div>' +
      '<button class="btn" data-act="clear-filter">' + esc(t('detailClearFilter')) + '</button></div>';
  }
  return '<div class="empty"><div class="et">' + esc(t('taskListEmpty')) + '</div>' +
    '<div class="es">' + esc(t('taskListEmptyFirstRun')) + '</div></div>';
}

function renderRows(): void {
  const all = store.visible();
  const open = all.filter((x) => !x.completed);
  const done = all.filter((x) => x.completed);
  let html = '';
  if (store.state.view === 'completed') {
    html = all.length ? all.map(rowHTML).join('') : emptyHTML();
  } else if (!all.length) {
    html = emptyHTML();
  } else {
    html = open.map(rowHTML).join('');
    if (!open.length) html += '<div class="allclear">' + esc(t('viewAllClear')) + '</div>';
    if (done.length) {
      html += '<button class="fold" data-act="fold" aria-expanded="' + store.state.doneOpen + '">' +
        (store.state.doneOpen ? ICONS.chevDown : ICONS.chevRight) + esc(t('navCompleted')) + ' ' + done.length + '</button>';
      html += '<div class="donegroup"' + (store.state.doneOpen ? '' : ' hidden') + '>' + done.map(rowHTML).join('') + '</div>';
    }
  }
  $('#rows')!.innerHTML = html;
  const card = $('#dpop')!;
  if (openId != null) {
    const row = $('.row[data-id="' + openId + '"]');
    if (row) place(card, row, $('.pane')!);
    else card.hidden = true;
  } else card.hidden = true;
}

function renderStatus(): void {
  const m = viewMeta();
  $('#statusLeft')!.textContent = m.title + ' · ' + t('subtitleOpenTasks', m.openN);
}

function render(): void {
  applyStaticI18n();
  renderSidebar();
  renderHeader();
  renderRows();
  renderStatus();
  refreshDatabaseUI();
}

/* ---- inline editor ---- */
function syncDraft(): void {
  const titleEl = $<HTMLInputElement>('#etitle');
  const noteEl = $<HTMLTextAreaElement>('.enotes');
  if (titleEl && draft) draft.text = titleEl.value;
  if (noteEl && draft) draft.notes = noteEl.value;
}

async function commitEdit(save: boolean): Promise<void> {
  if (editing == null) return;
  const task = store.taskById(editing);
  const id = editing;
  editing = null;
  const d = draft;
  draft = null;
  if (save && task && d) {
    syncDraft();
    const text = d.text.trim();
    try {
      await store.saveTask({ ...task, text: text || task.text, dueDate: d.dueDate || null, dueTime: d.dueTime || null, priority: d.priority, notes: d.notes.trim() || null });
    } catch (e) {
      announce(t('detailSaveFailed', e instanceof Error ? e.message : String(e)));
    }
  }
  void id;
  render();
}

function openEdit(id: number): void {
  if (editing != null && editing !== id) void commitEdit(true);
  if (openId === id) closeDetail(false);
  const task = store.taskById(id);
  if (!task) return;
  editing = id;
  draft = { text: task.text, dueDate: task.dueDate || '', dueTime: task.dueTime || '', priority: task.priority, notes: task.notes || '' };
  render();
  const input = $<HTMLInputElement>('#etitle');
  if (input) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
}

function focusTitle(id: number): void {
  const btn = $('.row[data-id="' + id + '"] [data-act="edit"]');
  if (btn) { btn.focus(); return; }
  $('.tile[aria-current="true"], .lrow[aria-current="true"], .trow[aria-pressed="true"]')?.focus();
}

function updateChips(): void {
  if (!draft) return;
  const dc = $('#chipDate'), pc = $('#chipPrio');
  if (dc) dc.innerHTML = ICONS.calendar + '<span>' + esc(dateChip(draft)) + '</span>';
  if (pc) pc.innerHTML = ICONS.flag + '<span>' + esc(t('editorPrioChip', t(PRIO_KEYS[draft.priority] ?? 'prioNone'))) + '</span>';
}

function cycleDate(): void {
  if (!draft) return;
  syncDraft();
  const b = bucket({ dueDate: draft.dueDate });
  if (b === 'today') draft.dueDate = addDays(TODAY, 1);
  else if (b === 'future') { draft.dueDate = ''; draft.dueTime = ''; }
  else draft.dueDate = TODAY;
  updateChips();
}

function cyclePrio(): void {
  if (!draft) return;
  syncDraft();
  draft.priority = (draft.priority + 1) % 4;
  updateChips();
}

/* ---- detail popover (per-field autosave) ---- */
function currentDetail(): Task | undefined {
  return openId != null ? store.taskById(openId) : undefined;
}

function fillDetail(task: Task): void {
  prepareDetails(task);
  $<HTMLInputElement>('#fTitle')!.value = task.text;
  $<HTMLInputElement>('#fDate')!.value = task.dueDate || '';
  $<HTMLInputElement>('#fTime')!.value = task.dueTime || '';
  $<HTMLSelectElement>('#fRemind')!.value = 'none';
  $<HTMLTextAreaElement>('#fNote')!.value = task.notes || '';
  $<HTMLInputElement>('#fUrl')!.value = task.url || '';
  $<HTMLSelectElement>('#fList')!.innerHTML = store.snapshot.lists.map((l) =>
    '<option value="' + l.id + '">' + esc(l.name) + '</option>').join('');
  $<HTMLSelectElement>('#fList')!.value = String(task.listId);
  renderPrio(); renderCardTags(); renderSubs();
}

function renderPrio(): void {
  const task = currentDetail();
  $$('#fPrio [data-prio]').forEach((b) => {
    b.setAttribute('aria-pressed', String(!!task && Number(b.dataset.prio) === task.priority));
  });
}

function renderCardTags(): void {
  const task = currentDetail();
  if (!task) return;
  $('#fTags')!.innerHTML = task.tags.length ? task.tags.map((g) =>
    '<span class="tag tag-edit">#' + esc(g) + '<button data-dtag="' + esc(g) + '" aria-label="' + esc(t('removeTag')) + ' ' + esc(g) + '">' + ICONS.x + '</button></span>').join('')
    : '<span class="muted">' + esc(t('detailNoTags')) + '</span>';
}

function renderSubs(): void {
  const task = currentDetail();
  if (!task) return;
  $('#fSubs')!.innerHTML = task.subtasks.length ? task.subtasks.map((s, i) =>
    '<div class="sub"><input type="checkbox" id="sub' + i + '" data-sub="' + i + '"' + (s.done ? ' checked' : '') + '>' +
    '<label for="sub' + i + '">' + esc(s.text) + '</label>' +
    '<button class="subdel" data-dsub="' + i + '" aria-label="' + esc(t('removeSubtask')) + ': ' + esc(s.text) + '">' + ICONS.x + '</button></div>').join('')
    : '<span class="muted">' + esc(t('detailNoSubtasks')) + '</span>';
}

async function persistDetail(mut: (task: Task) => Task): Promise<void> {
  const task = currentDetail();
  if (!task) return;
  try {
    await store.saveTask(mut(task));
  } catch (e) {
    announce(t('detailSaveFailed', e instanceof Error ? e.message : String(e)));
    return;
  }
  const after = store.taskById(task.id);
  if (after && !store.inView(after)) {
    closeDetail(false);
    announce(t('taskMovedOutOfView'));
  }
}

function openDetail(id: number): void {
  if (editing != null) void commitEdit(true);
  const task = store.taskById(id);
  if (!task) return;
  if (openId === id) { closeDetail(true); return; }
  openId = id;
  delArmed = false;
  $('#fDelete')!.textContent = t('taskDelete');
  fillDetail(task);
  render();
  const input = $<HTMLInputElement>('#fTitle');
  if (input) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
}

function closeDetail(refocus: boolean): void {
  const id = openId;
  openId = null;
  $('#dpop')!.hidden = true;
  $$('.row.sel').forEach((r) => r.classList.remove('sel'));
  $$('.info[aria-expanded="true"]').forEach((b) => b.setAttribute('aria-expanded', 'false'));
  if (refocus && id != null) {
    const btn = $('.row[data-id="' + id + '"] [data-act="info"]');
    if (btn) btn.focus();
    else $('.tile[aria-current="true"], .lrow[aria-current="true"], .trow[aria-pressed="true"]')?.focus();
  }
}

/* ---- undo banner ---- */
function showUndo(task: Task): void {
  undoTask = task;
  $('#undoText')!.textContent = t('bannerTaskDeleted', task.text);
  $('#undoBanner')!.hidden = false;
  window.clearTimeout(undoTimer);
  undoTimer = window.setTimeout(hideUndo, 6000);
}
function hideUndo(): void {
  undoTask = null;
  $('#undoBanner')!.hidden = true;
}

/* ---- quick add ---- */
async function addTask(raw: string): Promise<void> {
  try {
    const created = await store.quickAdd(raw);
    if (!created) return;
    if (!store.inView(created)) {
      store.state.view = 'today'; store.state.listId = null; store.state.tag = null; store.state.q = '';
      $<HTMLInputElement>('#q')!.value = '';
      store.emit();
    }
    announce(t('statusTaskAdded'));
  } catch (e) {
    announce(t('detailSaveFailed', e instanceof Error ? e.message : String(e)));
  }
}

/* ---- events ---- */
function bind(): void {
  $('#filterBar')!.addEventListener('click', (e) => {
    if (!(e.target as HTMLElement).closest('[data-act="clear-filter"]')) return;
    store.state.tag = null; store.state.q = '';
    $<HTMLInputElement>('#q')!.value = '';
    void store.setSearch('');
  });

  $('.sidebar')!.addEventListener('click', (e) => {
    const el = e.target as HTMLElement;
    if (el.closest('.sidebar-settings')) { void openSettings(); return; }
    if (el.closest('.addlink')) { openListEditor(null); return; }
    const v = el.closest<HTMLElement>('[data-view]');
    const l = el.closest<HTMLElement>('[data-list]');
    const g = el.closest<HTMLElement>('[data-tag]');
    if (!v && !l && !g) return;
    if (editing != null) void commitEdit(true);
    closeDetail(false);
    if (v) { store.state.view = v.dataset.view as store.ViewKind; store.state.listId = null; store.state.tag = null; }
    else if (l) { store.state.view = 'list'; store.state.listId = Number(l.dataset.list); store.state.tag = null; }
    else if (g) { store.state.tag = store.state.tag === g.dataset.tag ? null : (g.dataset.tag || null); }
    render();
    const sel = v ? '[data-view="' + v.dataset.view + '"]' : l ? '[data-list="' + l.dataset.list + '"]' : '[data-tag="' + (g?.dataset.tag || '') + '"]';
    $(sel)?.focus();
  });

  $('#editListBtn')!.addEventListener('click', () => {
    if (store.state.listId != null) openListEditor(store.state.listId);
  });

  $('#rows')!.addEventListener('click', (e) => {
    const btn = (e.target as HTMLElement).closest<HTMLElement>('[data-act]');
    if (!btn) return;
    const rowEl = (e.target as HTMLElement).closest<HTMLElement>('.row');
    if (!rowEl) {
      if (btn.dataset.act === 'fold') { store.state.doneOpen = !store.state.doneOpen; render(); $('.fold')?.focus(); }
      else if (btn.dataset.act === 'clear-filter') {
        store.state.tag = null; store.state.q = '';
        $<HTMLInputElement>('#q')!.value = '';
        void store.setSearch('');
      }
      return;
    }
    const id = Number(rowEl.dataset.id);
    const act = btn.dataset.act;
    const tag = btn.dataset.tag;
    if (editing != null && editing !== id) void commitEdit(true);

    if (act === 'toggle') {
      const task = store.taskById(id);
      if (!task) return;
      void store.toggleTask(id, !task.completed).then(() => {
        if (!task.completed) store.state.doneOpen = true;
        render();
        const after = $('.row[data-id="' + id + '"] .check');
        const fold = $('.fold');
        if (after) after.focus();
        else if (fold) fold.focus();
        else $('.tile[aria-current="true"], .lrow[aria-current="true"], .trow[aria-pressed="true"]')?.focus();
        announce(t('statusUpdateTaskState'));
      });
    } else if (act === 'edit') {
      if (editing === id) { void commitEdit(true).then(() => focusTitle(id)); }
      else openEdit(id);
    } else if (act === 'info') {
      openDetail(id);
    } else if (act === 'tag') {
      if (editing != null) void commitEdit(true);
      store.state.tag = store.state.tag === tag ? null : (tag || null);
      render();
      $('.trow[aria-pressed="true"]')?.focus();
    } else if (act === 'save') {
      void commitEdit(true).then(() => { focusTitle(id); announce(t('statusTaskUpdated')); });
    } else if (act === 'cancel') {
      void commitEdit(false).then(() => focusTitle(id));
    } else if (act === 'cycle-date') {
      cycleDate();
    } else if (act === 'cycle-prio') {
      cyclePrio();
    }
  });

  $('#rows')!.addEventListener('keydown', (e) => {
    const row = (e.target as HTMLElement).closest<HTMLElement>('.row');
    const id = row ? Number(row.dataset.id) : 0;
    if (e.key === 'Enter' && !e.isComposing && (e.target as HTMLElement).id === 'etitle') {
      e.preventDefault();
      void commitEdit(true).then(() => focusTitle(id));
    }
    if (e.key === 'Escape' && editing != null) {
      e.preventDefault();
      void commitEdit(false).then(() => focusTitle(id));
    }
  });

  $('#q')!.addEventListener('input', (e) => {
    const value = (e.target as HTMLInputElement).value.trim();
    window.clearTimeout(searchTimer);
    searchTimer = window.setTimeout(() => { void store.setSearch(value); }, 150);
  });
  $('#q')!.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      (e.target as HTMLInputElement).value = '';
      store.state.q = '';
      void store.setSearch('');
      (e.target as HTMLInputElement).blur();
    }
  });

  const qa = $<HTMLInputElement>('#quickAdd')!;
  qa.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); void addTask(qa.value); qa.value = ''; }
    if (e.key === 'Escape') { qa.value = ''; qa.blur(); }
  });

  /* detail fields — per-field autosave */
  $('#fTitle')!.addEventListener('change', () => {
    const v = $<HTMLInputElement>('#fTitle')!.value.trim();
    if (v) void persistDetail((task) => ({ ...task, text: v }));
  });
  $('#fNote')!.addEventListener('change', () => {
    const v = $<HTMLTextAreaElement>('#fNote')!.value;
    void persistDetail((task) => ({ ...task, notes: v || null }));
  });
  $('#fUrl')!.addEventListener('change', () => {
    const v = $<HTMLInputElement>('#fUrl')!.value;
    void persistDetail((task) => ({ ...task, url: v || null }));
  });
  $('#fDate')!.addEventListener('change', () => {
    const v = $<HTMLInputElement>('#fDate')!.value;
    void persistDetail((task) => ({ ...task, dueDate: v || null, dueTime: v ? task.dueTime : null }));
    if (!v) $<HTMLInputElement>('#fTime')!.value = '';
  });
  $('#fTime')!.addEventListener('change', () => {
    const v = $<HTMLInputElement>('#fTime')!.value;
    void persistDetail((task) => ({ ...task, dueTime: v || null }));
  });
  $('#fRemind')!.addEventListener('change', (e) => {
    // Reminder offsets are staged for A2 / #131 (PRODUCT-SPEC §5b); the
    // engine schedules due-time reminders itself. Keep the control, say so.
    (e.target as HTMLSelectElement).value = 'none';
    announce(t('reminderStaged'));
  });
  $('#fList')!.addEventListener('change', () => {
    const v = Number($<HTMLSelectElement>('#fList')!.value);
    void persistDetail((task) => ({ ...task, listId: v }));
  });
  $('#fPrio')!.addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-prio]');
    if (!b) return;
    void persistDetail((task) => ({ ...task, priority: Number(b.dataset.prio) })).then(renderPrio);
  });
  $('#fTags')!.addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-dtag]');
    if (!b) return;
    const g = b.dataset.dtag;
    void persistDetail((task) => ({ ...task, tags: task.tags.filter((x) => x !== g) })).then(renderCardTags);
  });
  $('#fTagAdd')!.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.isComposing) return;
    e.preventDefault();
    const input = e.target as HTMLInputElement;
    const v = input.value.trim().replace(/^#/, '');
    if (v) void persistDetail((task) => task.tags.includes(v) ? task : { ...task, tags: [...task.tags, v] }).then(renderCardTags);
    input.value = '';
  });
  $('#fSubs')!.addEventListener('change', (e) => {
    const box = (e.target as HTMLElement).closest<HTMLInputElement>('[data-sub]');
    if (!box) return;
    const i = Number(box.dataset.sub);
    void persistDetail((task) => ({ ...task, subtasks: task.subtasks.map((s, j) => j === i ? { ...s, done: box.checked } : s) }));
  });
  $('#fSubs')!.addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-dsub]');
    if (!b) return;
    const i = Number(b.dataset.dsub);
    void persistDetail((task) => ({ ...task, subtasks: task.subtasks.filter((_, j) => j !== i) })).then(renderSubs);
  });
  $('#fSubAdd')!.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.isComposing) return;
    e.preventDefault();
    const input = e.target as HTMLInputElement;
    const v = input.value.trim();
    if (v) void persistDetail((task) => ({ ...task, subtasks: [...task.subtasks, { text: v, done: false }] })).then(renderSubs);
    input.value = '';
  });
  $('#fDelete')!.addEventListener('click', () => {
    if (openId == null) return;
    if (!delArmed) {
      delArmed = true;
      $('#fDelete')!.textContent = t('confirmDeleteTask');
      window.setTimeout(() => {
        delArmed = false;
        const el = $('#fDelete');
        if (el) el.textContent = t('taskDelete');
      }, 3000);
      return;
    }
    const id = openId;
    closeDetail(false);
    void store.removeTask(id).then((gone) => {
      if (gone) showUndo(gone);
      announce(t('statusTaskDeleted'));
      $('.tile[aria-current="true"], .lrow[aria-current="true"], .trow[aria-pressed="true"]')?.focus();
    });
  });
  $('#dpop')!.addEventListener('click', (e) => {
    if ((e.target as HTMLElement).closest('[data-act="close-detail"]')) closeDetail(true);
  });

  $('#undoBtn')!.addEventListener('click', () => {
    const task = undoTask;
    hideUndo();
    if (task) void store.undoRemove(task).then(() => announce(t('undoRestored')));
  });

  $('.rows')!.addEventListener('scroll', () => {
    if (openId == null) return;
    const row = $('.row[data-id="' + openId + '"]');
    if (row) place($('#dpop')!, row, $('.pane')!);
  });

  document.addEventListener('pointerdown', (e) => {
    const el = e.target as HTMLElement;
    if (editing != null && !el.closest('.row.editing') && !el.closest('#rows')) {
      void commitEdit(true);
    }
    if (openId != null && !el.closest('#dpop') && !el.closest('[data-act="info"]')) {
      closeDetail(false);
    }
  });

  document.addEventListener('keydown', (e) => {
    if (!store.dbOpen || document.querySelector('dialog[open]')) return;
    if (!$('#settingsSheetWrap')!.hidden || !$('listSheetWrap')!.hidden) return;
    if (e.key === 'Escape') {
      if (openId != null) { closeDetail(true); return; }
      if (editing != null) { void commitEdit(false); return; }
    }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); $('#q')?.focus(); return; }
    if (e.key === '/' && !/^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement as HTMLElement).tagName)) {
      e.preventDefault(); $('#q')?.focus();
    }
  });
}

/* ---- boot ---- */
async function main(): Promise<void> {
  setLang(resolveLang('system'));
  initTheme();
  fillIcons();
  initDatabaseFlow();
  initListEditor();
  initSettings();
  bind();
  store.onChange(render);
  const result = await store.boot();
  if (result.mode === 'ok') {
    setLang(resolveLang(store.settings.language));
    applyTheme();
  } else {
    setGateMode(result.mode, result.error);
  }
  render();
}

void main();