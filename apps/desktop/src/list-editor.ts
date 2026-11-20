// List editor sheet — icon catalog + 12-color semantic palette, ported
// from design/prototype/list-editor.html onto create_list / update_list /
// delete_list. Colors ride the engine's ARGB integers (shared.ts palette).
import { t } from './i18n';
import * as store from './store';
import { announce, esc, fillIcons, listColorStyle, SWATCHES, tokenToArgb } from './shared';

const EMOJIS: Record<string, string[]> = {
  frequent: ['📋', '⭐', '❤️', '🔥', '✅', '📌', '💡', '🎯', '🗓', '💤', '🎁', '☕'],
  people: ['😀', '😎', '🧑‍💻', '👩‍🎨', '🧑‍🔬', '👶', '🧓', '🧑‍🍳', '🧑‍🏫', '👮', '🧑‍🌾', '🧑‍🚀'],
  nature: ['🌱', '🌿', '🍀', '🌵', '🌲', '🌸', '🌻', '🍁', '🌙', '☀️', '⛰️', '🌊'],
  food: ['🍜', '🍣', '🍱', '🥗', '🍎', '🍰', '🥟', '🍇', '🍳', '🍕', '🍺', '🧁'],
  activity: ['🏃', '🚴', '🏊', '🧘', '⚽', '🎾', '🏀', '🎿', '🎨', '🎸', '🎮', '🧩'],
  travel: ['✈️', '🚄', '🚗', '🗺️', '🏖️', '🏕️', '🧳', '🎫', '🏨', '🗼', '🚢', '🚲'],
  objects: ['💻', '📱', '⌚️', '🎧', '📷', '📚', '✏️', '🔑', '💳', '🧰', '🪑', '🕯️'],
  symbols: ['✅', '⚠️', '❗', '❓', '➕', '➖', '⭐', '🔥', '💤', '🎯', '📌', '💡'],
};
const CATS = Object.keys(EMOJIS);

let category = 'frequent';
let editingId: number | null = null;
let isNew = false;
let draft = { name: '', emoji: '📋', token: 'var(--list-blue)' };
let deleteArmed = false;

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;

function renderTabs(): void {
  $('iconTabs').innerHTML = CATS.map((cat) =>
    '<button class="tab" role="tab" data-cat="' + cat + '" aria-selected="' + (category === cat) + '" tabindex="' + (category === cat ? '0' : '-1') + '">' + esc(t('emojiCat_' + cat)) + '</button>').join('');
}
function renderGrid(): void {
  $('iconGrid').innerHTML = (EMOJIS[category] ?? []).map((e) =>
    '<button class="emo" data-emoji="' + e + '" aria-pressed="' + (draft.emoji === e) + '" aria-label="' + esc(t('dialogSelectIcon')) + ' ' + e + '">' + e + '</button>').join('');
}
function renderSwatches(): void {
  $('swatches').innerHTML = SWATCHES.map((s) => {
    const on = draft.token === s.token;
    return '<button class="swatch" data-color="' + s.token + '" aria-pressed="' + on + '" aria-label="' + esc(s.name) + '" style="background:' + s.token + ';color:' + s.ink + '">' + (on ? '✓' : '') + '</button>';
  }).join('');
}
function syncPreview(): void {
  $('previewDot').textContent = draft.emoji;
  $('previewDot').style.background = draft.token;
}

export function openListEditor(id: number | null): void {
  isNew = id == null;
  editingId = id;
  deleteArmed = false;
  $('listDelete').textContent = t('deleteListBtn');
  $('listDelete').hidden = isNew;
  category = 'frequent';
  if (isNew) {
    draft = { name: '', emoji: '📋', token: 'var(--list-blue)' };
    $('sheetTitle').textContent = t('dialogCreateList');
  } else {
    const l = store.listById(id);
    if (!l) return;
    const hex = l.color != null ? '#' + (l.color & 0xffffff).toString(16).padStart(6, '0').toUpperCase() : '';
    const hit = SWATCHES.find((s) => s.hex === hex);
    draft = { name: l.name, emoji: l.icon || '📋', token: hit ? hit.token : 'var(--list-blue)' };
    $('sheetTitle').textContent = t('dialogEditList');
  }
  ($('listName') as HTMLInputElement).value = draft.name;
  ($('listName') as HTMLInputElement).placeholder = t('dialogInputListName');
  $('savedBadge').classList.remove('on');
  $('listSheetWrap').hidden = false;
  renderTabs(); renderGrid(); renderSwatches(); syncPreview();
  $('listName').focus();
  ($('listName') as HTMLInputElement).select();
}

function closeSheet(): void {
  $('listSheetWrap').hidden = true;
}

async function saveSheet(): Promise<void> {
  const name = ($('listName') as HTMLInputElement).value.trim() || t('unnamedList');
  const color = tokenToArgb(draft.token);
  try {
    if (isNew) {
      const l = await store.createList(name, draft.emoji, color);
      store.state.view = 'list';
      store.state.listId = l.id;
      store.state.tag = null;
      store.emit();
    } else if (editingId != null) {
      const l = store.listById(editingId);
      if (l) await store.saveList({ ...l, name, icon: draft.emoji, color });
    }
  } catch (e) {
    announce(t('detailSaveFailed', e instanceof Error ? e.message : String(e)));
    return;
  }
  $('savedBadge').classList.add('on');
  announce(t('statusCreateList', name));
  window.setTimeout(() => $('savedBadge').classList.remove('on'), 1400);
  closeSheet();
}

async function deleteList(): Promise<void> {
  if (editingId == null) return;
  if (!deleteArmed) {
    deleteArmed = true;
    $('listDelete').textContent = t('confirmDeleteTask');
    window.setTimeout(() => {
      deleteArmed = false;
      const el = document.getElementById('listDelete');
      if (el) el.textContent = t('deleteListBtn');
    }, 3000);
    return;
  }
  const id = editingId;
  closeSheet();
  await store.removeList(id);
  announce(t('statusDeleteList'));
}

export function initListEditor(): void {
  $('iconTabs').addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-cat]');
    if (!b) return;
    category = b.dataset.cat || 'frequent';
    renderTabs(); renderGrid();
    $('iconTabs').querySelector<HTMLElement>('[data-cat="' + category + '"]')?.focus();
  });
  $('iconTabs').addEventListener('keydown', (e) => {
    const i = CATS.indexOf(category);
    if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      e.preventDefault();
      category = CATS[(i + (e.key === 'ArrowRight' ? 1 : CATS.length - 1)) % CATS.length] ?? 'frequent';
      renderTabs(); renderGrid();
      $('iconTabs').querySelector<HTMLElement>('[data-cat="' + category + '"]')?.focus();
    }
  });
  $('iconGrid').addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-emoji]');
    if (!b) return;
    draft.emoji = b.dataset.emoji || '📋';
    renderGrid(); syncPreview();
  });
  $('swatches').addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-color]');
    if (!b) return;
    draft.token = b.dataset.color || 'var(--list-blue)';
    renderSwatches(); syncPreview();
  });
  $('listName').addEventListener('input', () => {
    draft.name = ($('listName') as HTMLInputElement).value;
  });
  $('listCancel').addEventListener('click', closeSheet);
  $('listSave').addEventListener('click', () => { void saveSheet(); });
  $('listDelete').addEventListener('click', () => { void deleteList(); });
  $('listSheetWrap').addEventListener('pointerdown', (e) => {
    if (e.target === $('listSheetWrap')) closeSheet();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !$('listSheetWrap').hidden) closeSheet();
  });
  fillIcons($('listSheetWrap'));
}

export { listColorStyle };