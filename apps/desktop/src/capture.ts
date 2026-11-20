// Quick-capture popup (#141 slice 3) — the second, small web window the
// global hotkey opens (index.html#capture). Same backend, same engine:
// Enter commits through the same quick-add pipeline as the main pane
// (PRODUCT-SPEC §4), then the host closes the popup and pushes `changed`
// so the main window refetches. Esc closes without writing.
import * as rpc from '@taskly/core';
import { t, setLang, resolveLang } from './i18n';
import * as store from './store';
import { initTheme, applyTheme } from './theme';

export async function bootCapture(): Promise<void> {
  document.body.classList.add('capture-mode');
  document.body.innerHTML =
    '<div class="window capture-window"><div class="capture">' +
    '<input id="capInput" type="text" autocomplete="off">' +
    '<div class="cap-hint" id="capHint"></div>' +
    '<div class="cap-err" id="capErr" hidden></div>' +
    '</div></div>';
  const input = document.getElementById('capInput') as HTMLInputElement;
  const hint = document.getElementById('capHint') as HTMLElement;
  const err = document.getElementById('capErr') as HTMLElement;

  try { store.setSettings(await rpc.getSettings()); } catch { /* gate-less defaults */ }
  setLang(resolveLang(store.settings.language));
  initTheme();
  applyTheme();
  input.placeholder = t('capturePlaceholder');
  input.setAttribute('aria-label', t('capturePlaceholder'));
  hint.textContent = t('captureHint');

  // The popup never opens or creates a database: it only writes when the
  // engine already has one open (the main window owns the lifecycle).
  let open = false;
  try {
    await rpc.loadSnapshot('all', null, true);
    open = true;
  } catch {
    open = false;
  }
  store.setDbOpen(open);
  if (!open) {
    input.disabled = true;
    hint.textContent = t('captureNoDb');
  }
  input.focus();
  // Page-load signal for the real-window verifier (no eval on webviews).
  document.title = 'Taskly Capture Ready';

  const fail = (e: unknown): void => {
    err.hidden = false;
    err.textContent = t('detailSaveFailed', e instanceof Error ? e.message : String(e));
  };

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      void store.host.captureDone();
      return;
    }
    if (e.key !== 'Enter' || e.isComposing || !open) return;
    e.preventDefault();
    const raw = input.value;
    err.hidden = true;
    void (async () => {
      try {
        const created = await store.quickAdd(raw);
        void created;
        input.value = '';
        await store.host.captureDone();
      } catch (e2) {
        fail(e2);
      }
    })();
  });
}