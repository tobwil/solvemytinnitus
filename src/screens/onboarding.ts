import { h, btn, swap, progress, range, choices, callout } from '../ui/dom';
import { icon } from '../ui/icons';
import { store } from '../data/store';
import { engine } from '../audio/engine';
import { playTone, playNoise, Voice } from '../audio/synth';
import { navigate } from '../router';
import { Ear } from '../data/model';
import type { Params } from '../router';

const TOTAL = 4;

export function renderOnboarding(root: HTMLElement, params: Params): () => void {
  let step = Number(params.step ?? 1);
  const returning = store.get().settings.onboarded;
  let voice: Voice | null = null;
  const stop = () => { voice?.stop(60); voice = null; };
  const wrap = h('div', { class: 'page onb' });
  root.appendChild(wrap);

  const go = (n: number) => { stop(); step = n; render(); };

  function render() {
    if (step === 1) welcome();
    else if (step === 2) phones();
    else if (step === 3) volume();
    else profile();
  }

  function frame(content: Node[], actions: Node[]) {
    swap(wrap, h('div', null, returning ? null : progress(TOTAL, step), ...content), h('div', { class: 'btn-col' }, ...actions));
  }

  function welcome() {
    frame([
      heroArt(),
      h('p', { class: 'eyebrow' }, 'Willkommen'),
      h('h1', { class: 'title-xl' }, 'Dein persönliches Tinnitus-Labor'),
      h('p', { class: 'lead' }, 'Statt irgendeinem Rauschen findest du hier heraus, welcher Klang deinen Tinnitus nachweislich leiser macht, und trainierst gezielt damit. Kombiniert mit dem Verfahren, das in Studien am besten gegen die Belastung wirkt: kognitivem Training.'),
      h('ul', { class: 'list' },
        li('lab', 'Messen', 'Spektrum, Tonhöhe, Lautheit, Hörprofil, Somatik'),
        li('flask', 'Experimentieren', 'Verblindete Tests, welcher Klang bei dir wirkt'),
        li('sound', 'Trainieren', 'Personalisierte Klangtherapie und Kopf-Training'),
        li('trend', 'Auswerten', 'Was wirkt bei dir, belegt mit deinen Daten')),
    ], [btn('Los geht’s', () => go(2), { size: 'lg', block: true, iconRight: 'chevR' })]);
  }

  function phones() {
    let okL = false, okR = false;
    const mk = (ear: 'left' | 'right', label: string) => {
      const b = h('button', { type: 'button' }, icon('headphones'), label, h('span', { class: 'small' }, 'Tippen zum Abspielen'));
      b.addEventListener('click', async () => {
        await engine.ensure();
        stop();
        wrap.querySelectorAll('.lr button').forEach((x) => x.classList.remove('playing'));
        b.classList.add('playing');
        voice = playTone(1000, ear, -26);
        setTimeout(() => { stop(); b.classList.remove('playing'); b.classList.add('ok'); if (ear === 'left') okL = true; else okR = true; next.disabled = !(okL && okR); }, 1200);
      });
      return b;
    };
    const next = btn('Ja, links und rechts stimmen', () => {
      store.update((d) => (d.settings.headphonesOk = true));
      if (returning) navigate('/lab'); else go(3);
    }, { size: 'lg', block: true, disabled: true });
    frame([
      h('p', { class: 'eyebrow' }, 'Schritt 1'),
      h('h1', { class: 'title-l' }, 'Kopfhörer prüfen'),
      h('p', { class: 'body' }, 'Setz deine Kopfhörer auf. Tippe beide Seiten an und prüfe, ob der Ton auf dem richtigen Ohr ankommt. Für Töne über 10 kHz brauchst du gute Over-Ear- oder In-Ear-Kopfhörer, Lautsprecher funktionieren nicht.'),
      h('div', { class: 'lr mt16' }, mk('left', 'Links'), mk('right', 'Rechts')),
      callout('Kommt der Ton auf der falschen Seite an, hast du die Kopfhörer vertauscht. AirPods: Bluetooth funktioniert, aber deaktiviere „Adaptives Audio“ und „Geräuschunterdrückung“ für Messungen.'),
    ], [next, returning ? btn('Abbrechen', () => navigate('/lab'), { variant: 'text' }) : btn('Zurück', () => go(1), { variant: 'text' })]);
  }

  function volume() {
    const r = range({ label: 'App-Lautstärke', min: 5, max: 100, value: Math.round(engine.getMasterVolume() * 100), format: (v) => `${v} %`, onInput: (v) => engine.setMasterVolume(v / 100) });
    const play = btn('Referenzrauschen abspielen', async () => {
      await engine.ensure();
      if (voice) { stop(); play.lastChild!.textContent = 'Referenzrauschen abspielen'; return; }
      voice = playNoise('pink', 'both', -30);
      play.lastChild!.textContent = 'Stopp';
    }, { variant: 'ghost', block: true, icon: 'play' });
    frame([
      h('p', { class: 'eyebrow' }, 'Schritt 2'),
      h('h1', { class: 'title-l' }, 'Lautstärke festlegen'),
      h('p', { class: 'body' }, 'Stell die Lautstärke deines Geräts auf etwa 50 % und lass sie ab jetzt so. Regle dann hier, bis das Rauschen leise, aber klar hörbar ist, etwa so laut wie ein ruhiges Gespräch.'),
      h('div', { class: 'card mt16' }, play, r.el),
      callout('Kein Verfahren in dieser App wirkt besser, wenn es lauter ist. Leise ist sicher und meist wirksamer.', 'warn'),
    ], [btn('Passt so', () => { store.update((d) => (d.settings.masterVolume = r.input.valueAsNumber / 100)); go(4); }, { size: 'lg', block: true }), btn('Zurück', () => go(2), { variant: 'text' })]);
  }

  function profile() {
    let ear: Ear = store.get().settings.preferredEar;
    const name = h('input', { type: 'text', placeholder: 'Wie dürfen wir dich nennen? (optional)', value: store.get().settings.name }) as HTMLInputElement;
    frame([
      h('p', { class: 'eyebrow' }, 'Schritt 3'),
      h('h1', { class: 'title-l' }, 'Wo hörst du ihn?'),
      h('p', { class: 'body' }, 'Wir messen jedes Ohr getrennt, wenn sich der Tinnitus unterscheidet. Bei beidseitig gleichem Ton reicht „beide“.'),
      choices<Ear>([
        { value: 'both', title: 'Beide Ohren, etwa gleich', sub: 'Messung und Therapie binaural' },
        { value: 'left', title: 'Links lauter', sub: 'Wir beginnen links' },
        { value: 'right', title: 'Rechts lauter', sub: 'Wir beginnen rechts' },
      ], ear, (v) => (ear = v)),
      h('div', { class: 'mt16' }, name),
      callout(h('span', null, h('b', null, 'Ehrlich vorab: '), 'Chronischer Tinnitus nach Lärm ist heute nicht heilbar. Realistisch ist, die Lautheit bei einem Teil der Betroffenen messbar zu senken und die Belastung deutlich zu verringern. Diese App hilft dir, herauszufinden, was davon bei dir funktioniert.')),
    ], [btn('Programm starten', () => {
      store.update((d) => {
        d.settings.preferredEar = ear;
        d.settings.name = name.value.trim();
        d.settings.onboarded = true;
        d.settings.programStart = d.settings.programStart ?? new Date().toISOString();
      });
      navigate('/');
    }, { size: 'lg', block: true, variant: 'sound' }), btn('Zurück', () => go(3), { variant: 'text' })]);
  }

  render();
  return stop;
}

function li(ico: string, title: string, sub: string): HTMLElement {
  return h('li', null, h('span', { class: 'li-ico sound' }, icon(ico)), h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, title), h('div', { class: 'li-sub' }, sub)));
}

function heroArt(): SVGSVGElement {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 320 140');
  svg.setAttribute('class', 'hero-art');
  let paths = '';
  for (let k = 0; k < 6; k++) {
    let d = '';
    for (let x = 0; x <= 320; x += 4) {
      const env = Math.exp(-Math.pow((x - 160) / (60 + k * 14), 2));
      const y = 70 + Math.sin(x / (9 + k * 2.5) + k) * (46 - k * 6) * env;
      d += `${x ? 'L' : 'M'}${x},${y.toFixed(1)}`;
    }
    paths += `<path d="${d}" fill="none" stroke="url(#hg)" stroke-width="${2.4 - k * 0.3}" opacity="${1 - k * 0.14}" stroke-linecap="round"/>`;
  }
  svg.innerHTML = `<defs><linearGradient id="hg" x1="0" x2="1"><stop offset="0" stop-color="#5eead4" stop-opacity="0"/><stop offset=".3" stop-color="#5eead4"/><stop offset=".7" stop-color="#a78bfa"/><stop offset="1" stop-color="#a78bfa" stop-opacity="0"/></linearGradient></defs>${paths}<circle cx="160" cy="70" r="4" fill="#fbbf24"><animate attributeName="r" values="3;6;3" dur="2.4s" repeatCount="indefinite"/></circle>`;
  return svg;
}
