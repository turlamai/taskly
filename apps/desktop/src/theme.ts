// Theme application — engine setting is the authority (settings.theme),
// system appearance via prefers-color-scheme; tokens live in shared.css.
import { settings } from './store';

export function applyTheme(mode?: string): void {
  const m = mode || settings.theme || 'system';
  const dark = m === 'dark' || (m !== 'light' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.querySelectorAll('.window').forEach((w) => w.classList.toggle('dark', dark));
  document.documentElement.setAttribute('data-taskly-theme', dark ? 'dark' : 'light');
}

export function initTheme(): void {
  applyTheme();
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  mq.addEventListener('change', () => {
    if ((settings.theme || 'system') === 'system') applyTheme();
  });
}