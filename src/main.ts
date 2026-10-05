import './style.css';
import { h, clear } from './ui/dom';
import { store } from './data/store';
import { engine } from './audio/engine';
import { renderHome } from './screens/home';
import { renderHearing } from './screens/hearing';
import { renderMatching } from './screens/matching';
import { renderRiLab } from './screens/ri';
import { renderTherapy } from './screens/therapy';
import { renderJournal } from './screens/journal';
import { renderLearn } from './screens/learn';
import { renderSettings } from './screens/settings';
import { renderMeasure } from './screens/measure';

type Screen = (root: HTMLElement) => void | (() => void);

const routes: Record<string, Screen> = {
  '/': renderHome,
  '/measure': renderMeasure,
  '/hearing': renderHearing,
  '/match': renderMatching,
  '/ri': renderRiLab,
  '/therapy': renderTherapy,
  '/journal': renderJournal,
  '/learn': renderLearn,
  '/settings': renderSettings,
};

const tabs = [
  { path: '/', label: 'Start', ico: '◉' },
  { path: '/measure', label: 'Messen', ico: '〰' },
  { path: '/therapy', label: 'Therapie', ico: '♫' },
  { path: '/journal', label: 'Tagebuch', ico: '▤' },
  { path: '/learn', label: 'Wissen', ico: '✦' },
];

let cleanup: (() => void) | void;

function currentPath(): string {
  const hash = location.hash.replace(/^#/, '') || '/';
  return hash.split('?')[0];
}

export function navigate(path: string): void {
  location.hash = path;
}

function tabFor(path: string): string {
  if (['/hearing', '/match', '/ri', '/measure'].includes(path)) return '/measure';
  if (path === '/settings') return '/learn';
  return path;
}

function render(): void {
  const main = document.getElementById('main')!;
  if (cleanup) cleanup();
  cleanup = undefined;
  clear(main);
  const path = currentPath();
  const screen = routes[path] ?? renderHome;
  cleanup = screen(main);
  const active = tabFor(path);
  document.querySelectorAll('nav.tabs a').forEach((a) => {
    a.classList.toggle('active', (a as HTMLAnchorElement).dataset.path === active);
  });
  window.scrollTo(0, 0);
}

function buildShell(): void {
  const app = document.getElementById('app')!;
  engine.setMasterVolume(store.get().settings.masterVolume);
  const vol = h('input', { type: 'range', min: 0, max: 100, value: Math.round(store.get().settings.masterVolume * 100) }) as HTMLInputElement;
  vol.addEventListener('input', () => {
    const v = Number(vol.value) / 100;
    engine.setMasterVolume(v);
  });
  vol.addEventListener('change', () => {
    store.update((d) => (d.settings.masterVolume = Number(vol.value) / 100));
  });
  const header = h(
    'header',
    { class: 'app-header' },
    h('div', { class: 'header-inner' }, h('div', { class: 'brand' }, h('span', { class: 'dot' }), 'Tinnitus Lab'), h('label', { class: 'volume' }, '🔈', vol)),
  );
  const main = h('main', { id: 'main' });
  const nav = h(
    'nav',
    { class: 'tabs' },
    ...tabs.map((t) => h('a', { href: `#${t.path}`, 'data-path': t.path }, h('span', { class: 'ico' }, t.ico), t.label)),
  );
  app.append(header, main, nav);
}

export function toast(msg: string): void {
  const t = h('div', { class: 'toast' }, msg);
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 2200);
}

buildShell();
window.addEventListener('hashchange', render);
render();

// Unlock audio on first interaction (iOS)
const unlock = () => {
  engine.ensure();
  window.removeEventListener('pointerdown', unlock);
  window.removeEventListener('keydown', unlock);
};
window.addEventListener('pointerdown', unlock);
window.addEventListener('keydown', unlock);

if ('serviceWorker' in navigator && !location.hostname.includes('localhost')) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  });
}
