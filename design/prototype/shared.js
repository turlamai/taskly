/* Taskly 原型共享工具：示例数据时钟、日期、图标、详情层定位 */
window.Taskly = (function () {
  const TODAY = '2026-11-12';

  const svg = function (body) {
    return '<svg class="icon" viewBox="0 0 16 16" aria-hidden="true" focusable="false">' + body + '</svg>';
  };
  const stroke = 'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"';

  const ICONS = {
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
    pencil: svg('<path d="M10.8 2.9l2.3 2.3-7.5 7.5-3 .7.7-3 7.5-7.5z" ' + stroke + '/>')
  };

  const esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  };

  function addDays(iso, n) {
    const p = iso.split('-').map(Number);
    const dt = new Date(p[0], p[1] - 1, p[2] + n);
    return dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0') + '-' + String(dt.getDate()).padStart(2, '0');
  }

  function fmtDate(iso) {
    if (!iso) return '';
    const p = iso.split('-').map(Number);
    return p[1] + '月' + p[2] + '日';
  }

  function bucket(t) {
    if (!t.date) return '';
    if (t.date < TODAY) return 'over';
    if (t.date === TODAY) return 'today';
    return 'future';
  }

  function dueText(t) {
    const b = bucket(t);
    if (!b) return '';
    if (b === 'over') return (t.date === addDays(TODAY, -1) ? '昨天' : fmtDate(t.date)) + ' · 已逾期';
    if (b === 'today') return '今天' + (t.time ? ' ' + t.time : '');
    return (t.date === addDays(TODAY, 1) ? '明天' : fmtDate(t.date)) + (t.time ? ' ' + t.time : '');
  }

  function place(card, row, container) {
    if (!card || !row || !container) return;
    card.hidden = false;
    const r = row.getBoundingClientRect();
    const c = container.getBoundingClientRect();
    const maxTop = Math.max(8, c.height - card.offsetHeight - 12);
    const top = Math.min(Math.max(r.top - c.top - 6, 8), maxTop);
    card.style.top = top + 'px';
    card.style.right = '16px';
  }

  function announce(msg) {
    const live = document.getElementById('live');
    if (!live) return;
    live.textContent = '';
    window.setTimeout(function () { live.textContent = msg; }, 30);
  }

  /* ==== 主题：全站唯一真源，设置页写入、各页读取 ==== */
  const THEME_KEY = 'taskly.theme';
  const themeListeners = [];
  let memTheme = null;

  function readTheme() {
    if (memTheme) return memTheme;
    try {
      const v = window.localStorage.getItem(THEME_KEY);
      if (v === 'light' || v === 'dark' || v === 'system') return v;
    } catch (e) { /* 存储不可用时退回系统外观 */ }
    return 'system';
  }

  function systemDark() {
    return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function applyTheme(mode) {
    const m = mode || readTheme();
    const dark = m === 'dark' || (m !== 'light' && systemDark());
    const wins = document.querySelectorAll('.window');
    Array.prototype.forEach.call(wins, function (w) { w.classList.toggle('dark', dark); });
    document.documentElement.setAttribute('data-taskly-theme', dark ? 'dark' : 'light');
    return { mode: m, dark: dark };
  }

  function notifyTheme(st) {
    themeListeners.forEach(function (fn) { try { fn(st); } catch (e) { /* 通知失败不影响主题 */ } });
  }

  function setTheme(mode) {
    const next = mode === 'light' || mode === 'dark' ? mode : 'system';
    memTheme = next;
    try { window.localStorage.setItem(THEME_KEY, next); } catch (e) { /* 仅当前页生效 */ }
    const st = applyTheme(next);
    notifyTheme(st);
    return st;
  }

  function initTheme() {
    const st = applyTheme(readTheme());
    if (window.matchMedia) {
      const mq = window.matchMedia('(prefers-color-scheme: dark)');
      const onSystem = function () {
        if (readTheme() === 'system') notifyTheme(applyTheme('system'));
      };
      if (mq.addEventListener) mq.addEventListener('change', onSystem);
      else if (mq.addListener) mq.addListener(onSystem);
    }
    return st;
  }

  const api = {
    TODAY: TODAY, ICONS: ICONS, esc: esc, addDays: addDays, fmtDate: fmtDate,
    bucket: bucket, dueText: dueText, place: place, announce: announce,
    theme: {
      get: readTheme,
      set: setTheme,
      apply: applyTheme,
      init: initTheme,
      onChange: function (fn) { if (typeof fn === 'function') themeListeners.push(fn); }
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { api.theme.init(); });
  } else {
    api.theme.init();
  }

  return api;
})();
