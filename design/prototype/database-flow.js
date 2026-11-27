/* Database lifecycle prototype. No native filesystem or SQLite operations. */
(function () {
  const T = window.Taskly;
  const root = document.getElementById('app');
  if (!T || !root) return;
  const main = root.hasAttribute('data-database-main');
  const query = new URLSearchParams(location.search);
  let scenario = query.get('db-state') || '';
  function readRegistry() {
    try {
      const registry = JSON.parse(T.preferences.get('databases.v1', 'null'));
      if (registry && Array.isArray(registry.records)) return registry;
    } catch (error) { /* Start with an empty registry if the snapshot cannot be read. */ }
    return { active: null, records: [] };
  }
  let state = readRegistry();
  // ?db-state=empty shows the first-run canvas without touching the registry.
  if (scenario === 'empty') { state = { active: null, records: [] }; readRegistry = function () { return { active: null, records: [] }; }; }
  // ?db-state=missing needs a recorded database to lose.
  if (scenario === 'missing' && !state.records.length) {
    state = { active: 'db-lost', records: [{ id: 'db-lost', name: '工作', path: 'D:\\Sync\\Taskly\\工作\\taskly.sqlite', tasks: [] }] };
  }
  const defaultLists = {
    work:      { name: '工作', emoji: '💼', color: 'var(--list-cyan)' },
    home:      { name: '家',   emoji: '🏠', color: 'var(--list-green)' },
    important: { name: '重要', emoji: '⭐', color: 'var(--list-orange)' },
    reading:   { name: '读书', emoji: '📚', color: 'var(--list-indigo)' }
  };
  let blocked = scenario === 'missing';
  let mode = 'create';
  let confirmMigration = false;
  let trigger = null;
  const last = function () { return state.records.find(function (db) { return db.id === state.active; }) || null; };
  const current = function () { return blocked ? null : last(); };
  function persist() { return T.preferences.set('databases.v1', JSON.stringify(state)); }
  function commit() {
    persist();
    update();
    document.dispatchEvent(new CustomEvent('taskly:database', { detail: { database: current() } }));
  }
  const canonical = function (path) { return path.trim().replace(/\\/g, '/').replace(/\/+$/, ''); };

  // There is no separate gate page: the main window always shows, and the
  // canvas carries the no-database state (first run / last one missing).
  // Create / open live in that state, and once a database is open they sit
  // behind the database name in the sidebar footer.
  let menuTrigger = null;
  const canvasState = document.createElement('div');
  canvasState.className = 'dbstate';
  canvasState.id = 'dbState';
  canvasState.setAttribute('aria-labelledby', 'dbStateTitle');
  canvasState.hidden = true;
  canvasState.innerHTML = '<h2 id="dbStateTitle"></h2><p id="dbStateBody"></p>' +
    '<p class="dbstate-path" id="dbStatePath" hidden></p>' +
    '<p class="database-error" id="databaseGateError" role="alert" hidden></p>' +
    '<div class="database-choice" id="dbStateActions"></div>';
  if (main) root.querySelector('.pane').insertBefore(canvasState, root.querySelector('.statusbar'));
  const CANVAS_ACTIONS = {
    empty: [['create', '创建数据库…', 'primary'], ['open', '打开已有数据库…', '']],
    blocked: [['relocate', '重新定位…', 'primary'], ['retry', '重试', ''], ['open', '打开已有数据库…', '']]
  };
  function closeMenu(restoreFocus) {
    const menu = document.getElementById('dbMenu');
    if (!menu || menu.hidden) return;
    menu.hidden = true;
    document.getElementById('dbMenuBtn').setAttribute('aria-expanded', 'false');
    if (restoreFocus && menuTrigger) menuTrigger.focus();
  }

  const dialog = document.createElement('dialog');
  dialog.className = 'database-dialog';
  dialog.setAttribute('aria-labelledby', 'databaseDialogTitle');
  dialog.innerHTML = '<h2 id="databaseDialogTitle">创建数据库</h2><p id="databaseDialogDescription"></p>' +
    '<div id="databaseFields"><label class="field" id="databaseNameField"><span class="flabel">数据库名称</span><input class="input" id="databaseName" maxlength="64" autocomplete="off" value="我的任务"></label>' +
    // Same shape as the product: the path is read-only and comes from the
    // system picker. The prototype cannot open a native dialog, so the
    // button stands in for it and returns a demo location.
    '<div class="field"><div class="flabel" id="databasePathLabel">保存文件夹</div><div class="database-pickrow"><input class="input" id="databasePath" readonly maxlength="500" placeholder="尚未选择" aria-describedby="databasePathHelp databaseError"><button class="btn" type="button" id="databasePick">选择文件夹…</button></div><p class="database-help" id="databasePathHelp"></p></div></div>' +
    '<p class="database-confirm" id="databaseConfirm" hidden></p><p class="database-error" id="databaseError" role="alert" hidden></p>' +
    '<div class="database-actions"><button class="btn" type="button" id="databaseCancel">取消</button><button class="btn primary" type="button" id="databaseApply">创建并打开</button></div>';
  root.appendChild(dialog);
  const $ = function (id) { return dialog.querySelector('#' + id); };
  function fail(text) {
    $('databaseError').hidden = false;
    $('databaseError').textContent = text;
    $('databasePath').setAttribute('aria-invalid', 'true');
    $('databasePick').focus();
  }
  function clearError() {
    $('databaseError').hidden = true;
    $('databaseError').textContent = '';
    $('databasePath').removeAttribute('aria-invalid');
  }
  // Stands in for the native folder / file picker the product opens.
  $('databasePick').addEventListener('click', function () {
    const isFile = mode === 'open' || mode === 'relocate';
    $('databasePath').value = isFile
      ? 'D:\\Sync\\Taskly\\工作\\taskly.sqlite'
      : mode === 'migrate' ? 'D:\\Sync\\Taskly\\新位置' : 'D:\\Sync\\Taskly\\我的任务';
    clearError();
    $('databaseApply').focus();
  });
  function select(nextMode, button) {
    if (nextMode === 'retry') {
      // The failure specimen resolves on retry; a native host would check the file.
      blocked = false; scenario = ''; commit(); return;
    }
    if ((nextMode === 'migrate' || nextMode === 'reveal') && !current()) return;
    trigger = button || document.activeElement;
    mode = nextMode;
    confirmMigration = false;
    const db = last();
    const titles = { create: '创建数据库', open: '打开已有数据库', migrate: '迁移数据库', relocate: '重新定位数据库', reveal: '所在文件夹' };
    $('databaseDialogTitle').textContent = titles[mode];
    $('databaseDialogDescription').textContent = mode === 'create'
      ? '在指定文件夹中创建 taskly.sqlite。'
      : mode === 'open' ? '选择要打开的数据库文件。'
      : mode === 'migrate' ? '选择目标文件夹，再确认迁移。原生应用应在迁移成功后切换，失败时继续使用原位置。此处仅模拟。'
      : mode === 'relocate' ? '选择原数据库文件现在的位置。'
      : '原生应用会在系统文件管理器中显示此文件夹。当前原型无法打开系统目录。';
    $('databaseFields').hidden = mode === 'reveal';
    $('databaseNameField').hidden = mode !== 'create';
    $('databaseName').value = '我的任务';
    const isFile = mode === 'open' || mode === 'relocate';
    $('databasePathLabel').textContent = isFile ? '数据库文件' : '保存文件夹';
    $('databasePick').textContent = isFile ? '选择文件…' : '选择文件夹…';
    $('databasePath').value = mode === 'relocate' && db ? db.path : '';
    $('databasePathHelp').textContent = '原型里按钮返回一个示例位置；产品中打开系统文件夹 / 文件选择框。';
    $('databaseConfirm').hidden = mode !== 'reveal';
    $('databaseConfirm').textContent = db ? db.path.replace(/[/\\][^/\\]+$/, '') : '';
    $('databaseCancel').hidden = mode === 'reveal';
    $('databaseApply').textContent = mode === 'create' ? '创建并打开' : mode === 'migrate' ? '继续' : mode === 'reveal' ? '知道了' : '打开';
    clearError();
    dialog.showModal();
    (mode === 'reveal' ? $('databaseApply') : mode === 'create' ? $('databaseName') : $('databasePick')).focus();
  }
  function apply() {
    if (mode === 'reveal') { dialog.close(); return; }
    let path = canonical($('databasePath').value);
    const name = $('databaseName').value.trim();
    if (!path) { fail('请选择一个位置。当前数据库保持不变。'); return; }
    if (mode === 'create' && (!name || /[\\/:*?"<>|]/.test(name))) {
      fail('请填写名称，且不要包含 / \\ : * ? " < > |。'); $('databaseName').focus(); return;
    }
    if ((mode === 'open' || mode === 'relocate') && !/\.(sqlite|sqlite3|db)$/i.test(path)) {
      fail('请选择以 .sqlite、.sqlite3 或 .db 结尾的数据库文件。'); return;
    }
    if (mode === 'create' || mode === 'migrate') path += '/taskly.sqlite';
    const existing = state.records.find(function (db) { return canonical(db.path) === path; });
    if (mode === 'create' && existing) { fail('这个位置已有数据库。请更换位置，或取消后选择“打开已有数据库”。不会覆盖原有内容。'); return; }
    if ((mode === 'migrate' || mode === 'relocate') && existing && existing.id !== state.active) { fail('目标位置已有另一个数据库。请另选位置，不会覆盖它。'); return; }
    if (mode === 'migrate' && existing && existing.id === state.active) { fail('目标与当前位置相同，请选择另一个文件夹。'); return; }
    const expectedFailure = (mode === 'create' && scenario === 'create-failed') || ((mode === 'open' || mode === 'relocate') && scenario === 'open-failed') || (mode === 'migrate' && scenario === 'migrate-failed');
    if (expectedFailure) {
      scenario = '';
      fail(mode === 'create' ? '无法创建数据库：目标目录不可写。请选择其他位置或重试；未创建数据库。' : mode === 'migrate' ? '迁移未完成：目标位置无法写入。原位置和任务保持不变，可以重试。' : '无法打开数据库：文件不可读取或格式不受支持。请选择其他文件或重试；当前数据库保持不变。'); return;
    }
    if (mode === 'migrate' && !confirmMigration) {
      confirmMigration = true;
      $('databaseFields').hidden = true;
      $('databaseConfirm').hidden = false;
      $('databaseConfirm').textContent = '从：' + last().path + '\n迁移到：' + path + '\n全部任务随数据库保留。只有成功后才切换位置；失败时保留原位置。此处仅模拟。';
      $('databaseApply').textContent = '确认迁移';
      $('databaseCancel').focus(); return;
    }
    if (mode === 'migrate' || mode === 'relocate') {
      const db = last();
      if (!db) { fail('没有可定位的数据库，请取消后打开已有数据库。'); return; }
      db.path = path;
    } else if (existing) {
      state.active = existing.id;
    } else {
      const record = { id: 'db-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8), name: mode === 'create' ? name : path.split('/').pop().replace(/\.[^.]+$/, ''), path: path, tasks: [] };
      state.records.push(record); state.active = record.id;
    }
    blocked = false;
    dialog.close();
    commit();
    T.announce(mode === 'migrate' ? '演示迁移已完成，任务保留。' : '已打开演示数据库。');
    const input = document.getElementById('quickAdd'); if (input) input.focus();
  }
  $('databaseCancel').addEventListener('click', function () { dialog.close(); });
  $('databaseApply').addEventListener('click', apply);
  dialog.addEventListener('keydown', function (event) {
    if (event.key === 'Enter' && event.target.tagName === 'INPUT') { event.preventDefault(); apply(); }
  });
  dialog.addEventListener('close', function () { clearError(); if (trigger && trigger.isConnected) trigger.focus(); });
  dialog.addEventListener('input', clearError);
  document.addEventListener('click', function (event) {
    const toggle = event.target.closest('#dbMenuBtn');
    const menu = document.getElementById('dbMenu');
    if (toggle && menu) {
      menuTrigger = toggle;
      if (menu.hidden) {
        const db = current();
        menu.querySelectorAll('[data-db-requires-open]').forEach(function (item) { item.hidden = !db; });
        menu.hidden = false;
        toggle.setAttribute('aria-expanded', 'true');
        menu.querySelector('button:not([hidden])').focus();
      } else closeMenu(true);
      return;
    }
    if (menu && !menu.hidden && !menu.contains(event.target)) closeMenu(false);
    const button = event.target.closest('[data-db-action]');
    if (button) { closeMenu(false); select(button.dataset.dbAction, button); }
  });
  document.addEventListener('keydown', function (event) { if (event.key === 'Escape') closeMenu(true); });
  function update() {
    const db = current();
    if (main) {
      // No database: the task surfaces step aside and the canvas explains.
      ['.phead', '#filterBar', '.quickadd', '.rows'].forEach(function (selector) {
        const node = root.querySelector(selector); if (node) node.hidden = !db;
      });
      canvasState.hidden = !!db;
      if (!db) {
        const kind = blocked && last() ? 'blocked' : 'empty';
        canvasState.querySelector('#dbStateTitle').textContent = kind === 'blocked' ? '找不到上次的数据库' : '还没有任务数据库';
        canvasState.querySelector('#dbStateBody').textContent = kind === 'blocked'
          ? '上次打开的数据库不在原位置。重新定位后继续，或者打开另一个。'
          : '数据库是一个 SQLite 文件，放在你选择的文件夹里，由你保管。';
        const path = canvasState.querySelector('#dbStatePath');
        path.hidden = kind !== 'blocked';
        path.textContent = kind === 'blocked' ? last().path : '';
        canvasState.querySelector('#databaseGateError').hidden = true;
        canvasState.querySelector('#dbStateActions').innerHTML = CANVAS_ACTIONS[kind].map(function (action) {
          return '<button class="btn ' + action[2] + '" type="button" data-db-action="' + action[0] + '">' + action[1] + '</button>';
        }).join('');
      }
      closeMenu(false);
      root.querySelector('.sidebar').classList.toggle('no-database', !db);
    }
    document.querySelectorAll('[data-db-name]').forEach(function (node) { node.textContent = db ? db.name : '尚未打开数据库'; });
    document.querySelectorAll('[data-db-path]').forEach(function (node) { node.textContent = db ? db.path : '创建或打开数据库后显示位置'; });
    document.querySelectorAll('[data-db-requires-open]').forEach(function (node) { node.disabled = !db; });
  }
  function saveFields(fields) {
    const db = current();
    if (!db) return false;
    // Keep data written by another prototype screen in the same registry.
    const latest = readRegistry();
    if (latest.active !== db.id) return false;
    const target = latest.records.find(function (record) { return record.id === db.id; });
    if (!target) return false;
    Object.assign(target, JSON.parse(JSON.stringify(fields)));
    state = latest;
    return persist();
  }
  T.database = {
    current: current, select: select, refresh: update,
    reload: function () { state = readRegistry(); update(); },
    readLists: function () {
      const db = current();
      return JSON.parse(JSON.stringify(db && db.lists ? db.lists : defaultLists));
    },
    saveList: function (id, list) {
      const db = current();
      if (!db) return false;
      const latest = readRegistry().records.find(function (record) { return record.id === db.id; });
      const lists = Object.assign({}, defaultLists, latest && latest.lists, { [id]: list });
      return saveFields({ lists: lists });
    },
    restoreTasks: function (backup) {
      const snapshot = { tasks: backup.tasks };
      if (backup.lists) snapshot.lists = Object.assign({}, this.readLists(), backup.lists);
      return saveFields(snapshot);
    }
  };
  T.demoData.read = function () {
    const db = current();
    return db ? { format: 'taskly-prototype', version: 1, tasks: db.tasks } : null;
  };
  T.demoData.save = function (tasks) { return saveFields({ tasks: tasks }); };
  update();
})();
