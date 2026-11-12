/* 首帧前应用已保存的主题，避免载入时先亮后暗的闪烁 */
(function () {
  var mode = 'system';
  try {
    var v = window.localStorage.getItem('taskly.theme');
    if (v === 'light' || v === 'dark' || v === 'system') mode = v;
  } catch (e) { /* 存储不可用时跟随系统 */ }
  var dark = mode === 'dark' || (mode !== 'light' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.setAttribute('data-taskly-theme', dark ? 'dark' : 'light');
})();
