import './style.css';
import { h, clear, iconBtn, sheet, range, toast } from './ui/dom';
import { icon } from './ui/icons';
import { store } from './data/store';
import { engine } from './audio/engine';
import { playNoise } from './audio/synth';
import { parseHash, navigate, back, Params } from './router';
import { renderHome } from './screens/home';
import { renderLab } from './screens/lab';
import { renderSpectrum } from './screens/spectrum';
import { renderMatching } from './screens/matching';
import { renderHearing } from './screens/hearing';
import { renderSomatic } from './screens/somatic';
import { renderRiLab } from './screens/ri';
import { renderTherapy } from './screens/therapy';
import { renderMind } from './screens/mind';
import { renderProgress } from './screens/progress';
import { renderCheckin } from './screens/checkin';
import { renderLearn } from './screens/learn';
import { renderSettings } from './screens/settings';
import { renderOnboarding } from './screens/onboarding';

export type Screen = (root: HTMLElement, params: Params) => void | (() => void);

interface Route {
  screen: Screen;
  tab: string;
  title?: string; // shows a back crumb with this parent label
  parent?: string;
}

const routes: Record<string, Route> = {
  '/': { screen: renderHome, tab: '/' },
  '/lab': { screen: renderLab, tab: '/lab' },
  '/spectrum': { screen: renderSpectrum, tab: '/lab', title: 'Labor', parent: '/lab' },
  '/match': { screen: renderMatching, tab: '/lab', title: 'Labor', parent: '/lab' },
  '/hearing': { screen: renderHearing, tab: '/lab', title: 'Labor', parent: '/lab' },
  '/somatic': { screen: renderSomatic, tab: '/lab', title: 'Labor', parent: '/lab' },
  '/ri': { screen: renderRiLab, tab: '/lab', title: 'Labor', parent: '/lab' },
  '/therapy': { screen: renderTherapy, tab: '/therapy' },
  '/mind': { screen: renderMind, tab: '/mind' },
  '/progress': { screen: renderProgress, tab: '/progress' },
  '/checkin': { screen: renderCheckin, tab: '/', title: 'Heute', parent: '/' },
  '/learn': { screen: renderLearn, tab: '/', title: 'Heute', parent: '/' },
  '/settings': { screen: renderSettings, tab: '/', title: 'Heute', parent: '/' },
  '/onboarding': { screen: renderOnboarding, tab: '' },
};

const tabs = [
  { path: '/', label: 'Heute', ico: 'home' },
  { path: '/lab', label: 'Labor', ico: 'lab' },
  { path: '/therapy', label: 'Klang', ico: 'sound' },
  { path: '/mind', label: 'Kopf', ico: 'mind' },
  { path: '/progress', label: 'Verlauf', ico: 'trend' },
];

let cleanup: (() => void) | void;
let crumb: HTMLElement;
let tabbar: HTMLElement;

function render(): void {
  const main = document.getElementById('main')!;
  if (cleanup) {
    try { cleanup(); } catch (e) { console.warn(e); }
  }
  cleanup = undefined;
  clear(main);
  let { path, params } = parseHash();
  if (!store.get().settings.onboarded && path !== '/onboarding') {
    path = '/onboarding';
    params = {};
  }
  const route = routes[path] ?? routes['/'];
  // header crumb
  clear(crumb);
  if (route.parent) {
    const b = h('button', { type: 'button' }, icon('chevL'), route.title ?? 'Zurück');
    b.addEventListener('click', () => (params.from ? back(route.parent) : navigate(route.parent!)));
    crumb.appendChild(b);
  } else if (path === '/') {
    crumb.appendChild(h('span', { style: 'display:flex;align-items:center;gap:8px;font-weight:700;color:var(--text)' }, logo(), 'Tinnitus Lab'));
  }
  tabbar.classList.toggle('hide', path === '/onboarding');
  tabbar.querySelectorAll('a').forEach((a) => a.classList.toggle('active', (a as HTMLAnchorElement).dataset.path === route.tab));
  cleanup = route.screen(main, params);
  window.scrollTo(0, 0);
}

function logo(): SVGSVGElement {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 32 32');
  svg.setAttribute('width', '26');
  svg.setAttribute('height', '26');
  svg.innerHTML = '<defs><linearGradient id="lg" x1="0" x2="1"><stop offset="0" stop-color="#5eead4"/><stop offset="1" stop-color="#a78bfa"/></linearGradient></defs><rect width="32" height="32" rx="9" fill="url(#lg)" opacity=".18"/><path d="M5 16c3 0 3-7 6-7s3 14 6 14 3-14 6-14 3 7 4 7" fill="none" stroke="url(#lg)" stroke-width="2.6" stroke-linecap="round"/>';
  return svg;
}

function openVolume(): void {
  let preview: ReturnType<typeof playNoise> | null = null;
  sheet((close) => {
    const r = range({
      label: 'App-Lautstärke', min: 0, max: 100, value: Math.round(engine.getMasterVolume() * 100), format: (v) => `${v} %`,
      onInput: (v) => engine.setMasterVolume(v / 100),
      onChange: (v) => store.update((d) => (d.settings.masterVolume = v / 100)),
    });
    const pv = h('button', { class: 'btn ghost block', type: 'button' }, icon('play'), 'Referenzrauschen anhören');
    pv.addEventListener('click', async () => {
      await engine.ensure();
      if (preview) { preview.stop(); preview = null; pv.lastChild!.textContent = 'Referenzrauschen anhören'; return; }
      preview = playNoise('pink', 'both', -30);
      pv.lastChild!.textContent = 'Stopp';
    });
    const done = h('button', { class: 'btn block mt8', type: 'button' }, 'Fertig');
    done.addEventListener('click', () => { preview?.stop(); close(); });
    return h('div', null,
      h('h2', { class: 'title-l' }, 'Lautstärke'),
      h('p', { class: 'body' }, 'Stelle die Gerätelautstärke einmalig so ein, dass das Referenzrauschen leise, aber klar hörbar ist, etwa wie ein ruhiges Gespräch. Danach nur noch hier regeln.'),
      r.el, pv, done);
  });
}

function buildShell(): void {
  const app = document.getElementById('app')!;
  engine.setMasterVolume(store.get().settings.masterVolume);
  crumb = h('div', { class: 'crumb' });
  const actions = h('div', { class: 'actions' },
    iconBtn('volume', openVolume, 'Lautstärke'),
    iconBtn('book', () => navigate('/learn'), 'Wissen'),
    iconBtn('gear', () => navigate('/settings'), 'Einstellungen'));
  const top = h('header', { class: 'topbar' }, crumb, actions);
  const main = h('main', { id: 'main' });
  tabbar = h('nav', { class: 'tabbar', 'aria-label': 'Hauptnavigation' },
    ...tabs.map((t) => h('a', { href: `#${t.path}`, 'data-path': t.path }, icon(t.ico), t.label)));
  app.append(top, main, tabbar);
}

buildShell();
window.addEventListener('hashchange', render);
render();

const unlock = () => {
  engine.ensure();
  window.removeEventListener('pointerdown', unlock);
  window.removeEventListener('keydown', unlock);
};
window.addEventListener('pointerdown', unlock);
window.addEventListener('keydown', unlock);

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}

export { navigate, toast };
