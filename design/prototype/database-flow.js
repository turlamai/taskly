/* Database lifecycle prototype. No native filesystem or SQLite operations. */
(function () {
  const T = window.Taskly;
  const root = document.getElementById('app');
  if (!T || !root) return;
  const main = root.hasAttribute('data-database-main');
  const query = new URLSearchParams(location.search);
  let scenario = query.get('db-state') || '';
  let state;
  try { state = JSON.parse(T.preferences.get('databases.v1', '{"active":null,"records":[]}')); }
  catch (e) { state = { active: null, records: [] }; }
  if (!state || !Array.isArray(state.records)) state = { active: null, records: [] };
  let blocked = scenario === 'missing';
  let mode = 'create';
  let confirmMigration = false;
  let trigger = null;
  const last = function () { return state.records.find(function (db) { return db.id === state.active; }) || null; };
  const current = function () { return blocked ? null : last(); };
  function persist() { T.preferences.set('databases.v1', JSON.stringify(state)); }
  function commit() {
    persist();
    update();
    document.dispatchEvent(new CustomEvent('taskly:database', { detail: { database: current() } }));
  }
  const canonical = function (path) { return path.trim().replace(/\\/g, '/').replace(/\/+$/, ''); };

  const gate = document.createElement('section');
  gate.className = 'database-gate';
  gate.setAttribute('aria-labelledby', 'databaseWelcomeTitle');
  gate.innerHTML = '<div class="database-intro"><span class="database-wordmark">Taskly</span><h1 id="databaseWelcomeTitle">任务有归处，位置由你定。</h1><p>选择自己的文件夹，创建任务数据库。也可以打开已有数据库，继续记录。</p></div>' +
    '<div class="database-choice"><button class="btn primary" type="button" data-db-action="create">创建数据库</button><button class="btn" type="button" data-db-action="open">打开已有数据库…</button></div>' +
    '<div class="database-recovery" id="databaseRecovery" hidden><h2>找不到上次的数据库</h2><p id="databaseMissingPath"></p><p>文件可能已移动，或所在磁盘尚未连接。重新定位原文件即可继续，不会自动新建或覆盖。</p><div class="database-actions"><button class="btn" type="button" data-db-action="relocate">重新定位…</button><button class="btn" type="button" data-db-action="retry">重试</button></div></div>' +
    '<p class="database-principle">无需绑定账号或云服务。数据的位置与同步方式由你管理。</p><p class="database-demo">交互原型：位置输入与数据库操作均为模拟，不会创建或读取真实 SQLite 文件。数据库之间的演示任务分开保存于本浏览器。</p>';
  if (main) root.insertBefore(gate, root.querySelector('.app'));

  const dialog = document.createElement('dialog');
  dialog.className = 'database-dialog';
  dialog.setAttribute('aria-labelledby', 'databaseDialogTitle');
  dialog.innerHTML = '<h2 id="databaseDialogTitle">创建数据库</h2><p id="databaseDialogDescription"></p>' +
    '<div id="databaseFields"><label class="field" id="databaseNameField"><span class="flabel">数据库名称</span><input class="input" id="databaseName" maxlength="64" autocomplete="off" value="我的任务"></label>' +
    '<label class="field"><span class="flabel" id="databasePathLabel">保存文件夹 · 演示</span><input class="input" id="databasePath" maxlength="500" autocomplete="off" placeholder="输入你选择的文件夹位置" aria-describedby="databasePathHelp databaseError"></label><p class="database-help" id="databasePathHelp"></p></div>' +
    '<p class="database-confirm" id="databaseConfirm" hidden></p><p class="database-error" id="databaseError" role="alert" hidden></p>' +
    '<div class="database-actions"><button class="btn" type="button" id="databaseCancel">取消</button><button class="btn primary" type="button" id="databaseApply">创建并打开</button></div>';
  root.appendChild(dialog);
  const $ = function (id) { return dialog.querySelector('#' + id); };
  function fail(text) {
    $('databaseError').hidden = false;
    $('databaseError').textContent = text;
    $('databasePath').setAttribute('aria-invalid', 'true');
    $('databasePath').focus();
  }
  function clearError() {
    $('databaseError').hidden = true;
    $('databaseError').textContent = '';
    $('databasePath').removeAttribute('aria-invalid');
  }
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
      ? '选择存储位置，Taskly 会在该文件夹内创建 taskly.sqlite。此原型仅模拟创建，成功后进入空白任务列表。'
      : mode === 'open' ? '正式应用会使用文件选择器。此处输入数据库文件位置演示打开流程；新位置进入空白演示，已在本原型登记的位置恢复其演示任务，不读取文件内容。'
      : mode === 'migrate' ? '先选择目标文件夹，再确认迁移。原生应用应在迁移成功后切换，失败时继续使用原位置。此处仅模拟。'
      : mode === 'relocate' ? '重新选择原来的数据库文件。演示会保留该库的任务；不会创建替代数据库或修改其他数据库。'
      : '原生应用会在系统文件管理器中显示此文件夹。当前原型无法打开系统目录。';
    $('databaseFields').hidden = mode === 'reveal';
    $('databaseNameField').hidden = mode !== 'create';
    $('databaseName').value = '我的任务';
    $('databasePathLabel').textContent = mode === 'open' || mode === 'relocate' ? '数据库文件位置 · 演示' : '保存文件夹 · 演示';
    $('databasePath').value = mode === 'relocate' && db ? db.path : '';
    $('databasePath').placeholder = mode === 'open' || mode === 'relocate' ? '例如：我的同步目录 / taskly.sqlite' : '例如：我的同步目录 / Taskly';
    $('databasePathHelp').textContent = '位置由你指定，不预设目录。此输入替代原生系统选择器，仅用于交互演示。';
    $('databaseConfirm').hidden = mode !== 'reveal';
    $('databaseConfirm').textContent = db ? db.path.replace(/[/\\][^/\\]+$/, '') : '';
    $('databaseCancel').hidden = mode === 'reveal';
    $('databaseApply').textContent = mode === 'create' ? '创建并打开' : mode === 'migrate' ? '继续' : mode === 'reveal' ? '知道了' : '打开';
    clearError();
    dialog.showModal();
    (mode === 'reveal' ? $('databaseApply') : mode === 'create' ? $('databaseName') : $('databasePath')).focus();
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
    const button = event.target.closest('[data-db-action]');
    if (button) select(button.dataset.dbAction, button);
  });
  function update() {
    const db = current();
    if (main) {
      root.querySelector('.app').hidden = !db;
      gate.hidden = !!db;
      const recovery = gate.querySelector('#databaseRecovery');
      recovery.hidden = !blocked;
      gate.querySelector('#databaseMissingPath').textContent = last() ? last().path : '上次记录的数据库位置不可用。';
      gate.querySelector('#databaseWelcomeTitle').textContent = blocked ? '重新连接你的数据库' : '任务有归处，位置由你定。';
    }
    document.querySelectorAll('[data-db-name]').forEach(function (node) { node.textContent = db ? db.name : '尚未打开数据库'; });
    document.querySelectorAll('[data-db-path]').forEach(function (node) { node.textContent = db ? db.path : '创建或打开数据库后显示位置'; });
    document.querySelectorAll('[data-db-requires-open]').forEach(function (node) { node.disabled = !db; });
  }
  T.database = { current: current, select: select, refresh: update };
  T.demoData.read = function () {
    const db = current();
    return db ? { format: 'taskly-prototype', version: 1, tasks: db.tasks } : null;
  };
  T.demoData.save = function (tasks) {
    const db = current();
    if (!db) return;
    db.tasks = JSON.parse(JSON.stringify(tasks)); persist();
  };
  update();
})();
