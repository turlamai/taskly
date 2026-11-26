// Shared UI utilities ported from design/prototype/shared.js — the
// prototype remains the visual source; this module only swaps the fake
// data clock/preferences for engine-backed state (see store.ts).
import type { Task } from '@taskly/core';
import { t as tr, getLang } from './i18n';

const now = new Date();
export const TODAY =
  now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-' + String(now.getDate()).padStart(2, '0');

const svg = (body: string) =>
  '<svg class="icon" viewBox="0 0 16 16" aria-hidden="true" focusable="false">' + body + '</svg>';
const stroke = 'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"';

export const ICONS: Record<string, string> = {
  today: svg('<rect x="2.4" y="3.6" width="11.2" height="10" rx="2" ' + stroke + '/><path d="M2.4 6.4h11.2M5.6 2.4v2.2M10.4 2.4v2.2" ' + stroke + '/><text x="8" y="12" text-anchor="middle" fill="currentColor" font-size="5.5" font-weight="700">' + now.getDate() + '</text>'),
  check: svg('<path d="M3.6 8.6l3 3 5.8-7" ' + stroke + '/>'),
  info: svg('<circle cx="8" cy="8" r="6.1" ' + stroke + '/><path d="M8 7.3v3.9" ' + stroke + '/><circle cx="8" cy="5.1" r=".85" fill="currentColor"/>'),
  calendar: svg('<rect x="2.4" y="3.6" width="11.2" height="10" rx="2" ' + stroke + '/><path d="M2.4 7h11.2M5.6 2.4v2.2M10.4 2.4v2.2" ' + stroke + '/>'),
  clock: svg('<circle cx="8" cy="8" r="6.1" ' + stroke + '/><path d="M8 4.9V8l2.1 1.3" ' + stroke + '/>'),
  flag: svg('<path d="M4.4 13V3.4h6.2l-1 2.1 1 2.1H4.4" ' + stroke + '/>'),
  tag: svg('<path d="M3 3h4.7l5.3 5.3-4.7 4.7L3 7.7V3z" ' + stroke + '/><circle cx="5.6" cy="5.6" r=".9" fill="currentColor"/>'),
  plus: svg('<path d="M8 3.4v9.2M3.4 8h9.2" ' + stroke + '/>'),
  search: svg('<circle cx="7.2" cy="7.2" r="4.2" ' + stroke + '/><path d="M10.4 10.4l3.2 3.2" ' + stroke + '/>'),
  lines: svg('<path d="M3 4.6h10M3 8h10M3 11.4h6.6" ' + stroke + '/>'),
  checkCircle: svg('<circle cx="8" cy="8" r="6.1" ' + stroke + '/><path d="M5.4 8.2l1.9 1.9 3.5-4.1" ' + stroke + '/>'),
  chevRight: svg('<path d="M6.4 4.2l3.8 3.8-3.8 3.8" ' + stroke + '/>'),
  chevDown: svg('<path d="M4.2 6.4l3.8 3.8 3.8-3.8" ' + stroke + '/>'),
  x: svg('<path d="M4.4 4.4l7.2 7.2M11.6 4.4l-7.2 7.2" ' + stroke + '/>'),
  theme: svg('<circle cx="8" cy="8" r="6.1" ' + stroke + '/><path d="M8 1.9a6.1 6.1 0 010 12.2z" fill="currentColor"/>'),
  trash: svg('<path d="M3.4 4.8h9.2M6.4 4.8V3.2h3.2v1.6M5.2 4.8l.5 8h4.6l.5-8" ' + stroke + '/>'),
  pencil: svg('<path d="M10.8 2.9l2.3 2.3-7.5 7.5-3 .7.7-3 7.5-7.5z" ' + stroke + '/>'),
};

export function esc(s: unknown): string {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string));
}

export function addDays(iso: string, n: number): string {
  const [y = 1970, m = 1, d = 1] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d + n);
  return dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0') + '-' + String(dt.getDate()).padStart(2, '0');
}

export function fmtDate(iso: string): string {
  if (!iso) return '';
  const [y = 1970, m = 1, d = 1] = iso.split('-').map(Number);
  const date = new Date(y, m - 1, d);
  return new Intl.DateTimeFormat(getLang() === 'zh' ? 'zh-CN' : 'en-US', { month: 'short', day: 'numeric' }).format(date);
}

export type Bucket = '' | 'over' | 'today' | 'future';
export function bucket(t: { dueDate?: string | null }): Bucket {
  const d = t.dueDate || '';
  if (!d) return '';
  if (d < TODAY) return 'over';
  if (d === TODAY) return 'today';
  return 'future';
}

export function dueText(t: Task): string {
  const b = bucket(t);
  if (!b) return '';
  const d = t.dueDate as string;
  const time = t.dueTime ? ' ' + t.dueTime : '';
  if (b === 'over') return (d === addDays(TODAY, -1) ? tr('dateYesterday') : fmtDate(d)) + ' · ' + tr('overdueSuffix');
  if (b === 'today') return tr('navToday') + time;
  return (d === addDays(TODAY, 1) ? tr('dateTomorrow') : fmtDate(d)) + time;
}

export function place(card: HTMLElement, row: HTMLElement, container: HTMLElement): void {
  card.hidden = false;
  const r = row.getBoundingClientRect();
  const c = container.getBoundingClientRect();
  // A clamped popover stops above the status bar so the bar stays readable.
  const bar = container.querySelector<HTMLElement>('.statusbar');
  const reserved = bar ? bar.offsetHeight : 0;
  const maxTop = Math.max(8, c.height - card.offsetHeight - 12 - reserved);
  const top = Math.min(Math.max(r.top - c.top - 6, 8), maxTop);
  card.style.top = top + 'px';
  card.style.right = '16px';
}

export function announce(msg: string): void {
  const live = document.getElementById('live');
  if (!live) return;
  live.textContent = '';
  window.setTimeout(() => { live.textContent = msg; }, 30);
}

/** Disclosure sections open automatically when the field holds a value. */
export function prepareDetails(t: Task): void {
  const visible: Record<string, boolean> = {
    time: !!t.dueTime,
    priority: !!t.priority,
    tags: t.tags.length > 0,
    subtasks: t.subtasks.length > 0,
    url: !!t.url,
  };
  document.querySelectorAll<HTMLElement>('[data-detail-field]').forEach((section) => {
    (section as HTMLDetailsElement).open = !!visible[section.dataset.detailField || ''];
  });
}

export function fillIcons(root: ParentNode = document): void {
  root.querySelectorAll<HTMLElement>('[data-icon]').forEach((el) => {
    el.innerHTML = ICONS[el.dataset.icon || ''] || '';
  });
}

/* ---- list palette: semantic tokens ↔ engine ARGB integers ----
   The engine stores signed-32-bit ARGB (default -16745729 = #007AFF).
   The web renders the semantic token so light/dark follow shared.css;
   unknown legacy colors fall back to their literal rgb value. */
export const SWATCHES: { name: string; token: string; hex: string; ink: string }[] = [
  { name: '蓝色', token: 'var(--list-blue)', hex: '#007AFF', ink: '#FFFFFF' },
  { name: '红色', token: 'var(--list-red)', hex: '#FF3B30', ink: '#FFFFFF' },
  { name: '橙色', token: 'var(--list-orange)', hex: '#FF9500', ink: '#1D1D1F' },
  { name: '黄色', token: 'var(--list-yellow)', hex: '#FFCC00', ink: '#1D1D1F' },
  { name: '绿色', token: 'var(--list-green)', hex: '#4CD964', ink: '#1D1D1F' },
  { name: '浅蓝', token: 'var(--list-cyan)', hex: '#5AC8FA', ink: '#1D1D1F' },
  { name: '靛蓝', token: 'var(--list-indigo)', hex: '#5856D6', ink: '#FFFFFF' },
  { name: '粉色', token: 'var(--list-pink)', hex: '#FF2D55', ink: '#FFFFFF' },
  { name: '灰色', token: 'var(--list-gray)', hex: '#8E8E93', ink: '#1D1D1F' },
  { name: '浅灰', token: 'var(--list-silver)', hex: '#C7C7CC', ink: '#1D1D1F' },
  { name: '棕色', token: 'var(--list-brown)', hex: '#A2845E', ink: '#1D1D1F' },
  { name: '青色', token: 'var(--list-teal)', hex: '#00C7BE', ink: '#1D1D1F' },
];

export function hexToArgb(hex: string): number {
  const n = parseInt(hex.slice(1), 16);
  return ((0xff << 24) | n) >> 0;
}

export function argbToHex(argb: number): string {
  return '#' + (argb & 0xffffff).toString(16).padStart(6, '0').toUpperCase();
}

/** CSS background for a stored list color: token when known, rgb otherwise. */
export function listColorStyle(argb: number | null | undefined): string {
  if (argb == null) return 'var(--accent)';
  const hex = argbToHex(argb);
  const hit = SWATCHES.find((s) => s.hex === hex);
  return hit ? hit.token : hex;
}

export function tokenToArgb(token: string): number {
  const hit = SWATCHES.find((s) => s.token === token);
  return hexToArgb(hit ? hit.hex : '#007AFF');
}

/* ---- client-side #tag extraction (engine parses @time / +Nd only) ---- */
export function extractTags(raw: string): { title: string; tags: string[] } {
  const tags: string[] = [];
  const re = /#([\p{L}\p{N}_-]+)/gu;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw)) !== null) { const g = m[1]; if (g && !tags.includes(g)) tags.push(g); }
  const title = raw.replace(re, '').replace(/\s+/g, ' ').trim();
  return { title, tags };
}