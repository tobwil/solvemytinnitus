import { h, btn, page, header, card, range, seg, callout, evidence, sheet, scale10, toast, fmtDuration, chip, sectionH } from '../ui/dom';
import { icon, solidIcon } from '../ui/icons';
import { ring } from '../ui/chart';
import { spectrumViz } from '../ui/viz';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playNoise, playNotchedNoise, playNotchedRain, playNotchedSource, playRain, playAmNoise, chime, Voice } from '../audio/synth';
import { CrStimulator, CR_RATIOS } from '../audio/cr';
import { StimulusKind, TherapyMode, TinnitusMatch } from '../data/model';
import { navigate, Params } from '../router';
import { STIMULI, bestRiStimulus, describeStimulus, startStimulus } from './ri';

interface ModeInfo { mode: TherapyMode; title: string; tagline: string; desc: string; level: 1 | 2 | 3 | 4; evidence: string; icon: string; dose: string }

export const MODES: ModeInfo[] = [
  { mode: 'enrichment', title: 'Klanganreicherung', tagline: 'Den Kontrast zur Stille nehmen', icon: 'rain', level: 2, dose: 'Tag & Nacht',
    desc: 'Leiser, angenehmer Hintergrundklang knapp unter der Maskierungsschwelle. Neu: personalisiertes, mit 10 Hz moduliertes Rauschen mit Betonung um deine Tinnitus-Frequenz.',
    evidence: 'Klangtherapie ist Teil der leitliniengerechten Beratung, allein aber schwach belegt. 10-Hz-moduliertes Rauschen senkte in einer nicht-randomisierten Studie (Sendesen 2026, n=71) die Maskierungsschwelle über 6 Monate stärker als unmoduliertes.' },
  { mode: 'reset', title: 'Reset-Sitzung', tagline: 'Dein bester RI-Klang, im Wechsel mit Stille', icon: 'wave', level: 1, dose: '2× täglich 10–15 min',
    desc: 'Dein im Labor wirksamster Klang im Wechsel mit Stille. In den Stille-Phasen erlebst du, dass dein Tinnitus veränderbar ist; das allein reduziert bei vielen die Belastung.',
    evidence: 'Residual Inhibition als Kurzzeiteffekt ist gut belegt (Roberts 2008). Dass Wiederholung dauerhaft wirkt, ist nicht nachgewiesen. Experimentell.' },
  { mode: 'notched', title: 'Notched Sound', tagline: 'Musik oder Rauschen mit Lücke bei deiner Frequenz', icon: 'note', level: 2, dose: '1–2 h täglich',
    desc: 'Klang mit einer Lücke um deine Tinnitus-Frequenz, gedacht um über laterale Hemmung die Überaktivität dort zu dämpfen. Funktioniert auch mit deiner eigenen Musik.',
    evidence: 'Frühe Studien positiv (Okamoto 2010). Neuere Meta-Analysen (Alfonso 2024, Tavanai 2024) finden keinen Vorteil gegenüber normaler Musik. Widersprüchlich.' },
  { mode: 'cr', title: 'CR-Neuromodulation', tagline: 'Vier Töne um deine Frequenz im Zufallstakt', icon: 'pulse', level: 1, dose: 'flexibel',
    desc: 'Vier Töne um deine Tinnitus-Frequenz in zufälliger Folge (Tass 2012). Sollte überaktive Nervenverbände entkoppeln.',
    evidence: 'Die große doppelblinde RESET2-Studie (Hall 2022, n=100) fand keinen Unterschied zu Placebo. Nur der Vollständigkeit halber enthalten.' },
];

export function modeTitle(m: string): string {
  return MODES.find((x) => x.mode === m)?.title ?? m;
}

export function renderTherapy(root: HTMLElement, params: Params): () => void {
  const match = store.latestMatch();
  if (!match) {
    root.appendChild(page(header('Klang', 'Klangtherapie'), callout('Alle Klänge werden auf deine Tinnitus-Frequenz zugeschnitten. Dafür brauchen wir zuerst eine Messung.', 'warn'), btn('Zur Messung', () => navigate('/spectrum'), { variant: 'lab', block: true, size: 'lg' })));
    return () => {};
  }
  if (params.mode && MODES.find((m) => m.mode === params.mode)) return player(root, params.mode as TherapyMode, match);
  const best = bestRiStimulus(store.get().riTrials);
  root.appendChild(page(
    header('Klang', 'Klangtherapie', `Zugeschnitten auf ${formatHz(match.freq)}${best ? ` · bester RI-Klang: ${describeStimulus(best.stimulus)}` : ''}`),
    card('glow-mind tap', h('div', { class: 'row' },
      h('span', { class: 'li-ico mind' }, icon('mind')),
      h('div', { class: 'grow' }, h('p', { class: 'title-m', style: 'margin:0' }, 'Am besten belegt: Kopf-Training'), h('p', { class: 'small', style: 'margin:2px 0 0' }, 'Kognitive Verhaltenstherapie senkt die Belastung zuverlässiger als jeder Klang. Kombiniere beides.')),
      icon('chevR', 'chev'))),
    sectionH('Klänge'),
    ...MODES.map((m) => {
      const c = card('tap',
        h('div', { class: 'row', style: 'align-items:flex-start' },
          h('span', { class: 'li-ico sound' }, icon(m.icon)),
          h('div', { class: 'grow' },
            h('p', { class: 'title-m', style: 'margin:0' }, m.title),
            h('p', { class: 'small', style: 'margin:2px 0 8px' }, m.tagline),
            h('div', { class: 'row wrap', style: 'gap:8px' }, evidence(m.level), chip(m.dose))),
          h('span', { class: 'icon-btn', style: 'background:var(--sound);color:var(--on-accent);border:none' }, solidIcon('play'))));
      c.addEventListener('click', () => navigate(`/therapy?mode=${m.mode}`));
      return c;
    }),
  ));
  root.querySelector('.glow-mind')!.addEventListener('click', () => navigate('/mind'));
  return () => {};
}

// ---------------------------------------------------------------------------------------- player

interface Running { stop(): void; setLevel(db: number): void }

function player(root: HTMLElement, mode: TherapyMode, m: TinnitusMatch): () => void {
  const info = MODES.find((x) => x.mode === mode)!;
  const d = store.get();
  const best = bestRiStimulus(d.riTrials);
  const mml = m.mmlDb ?? m.loudnessDb;
  const p = {
    level: mode === 'enrichment' ? Math.min(-10, mml - 6) : mode === 'reset' ? Math.min(-8, mml + 10) : mode === 'cr' ? Math.min(-14, m.loudnessDb) : Math.min(-12, mml),
    source: mode === 'enrichment' ? 'am' : 'pink',
    width: d.settings.notchWidthOctaves,
    stimulus: (best?.stimulus ?? 'nbn-third') as StimulusKind,
    onS: 30,
    offS: 60,
    targetMin: mode === 'reset' ? 12 : mode === 'enrichment' ? 30 : 60,
  };
  let running: Running | null = null;
  let elapsed = 0;
  let tick: number | null = null;
  let pre: number | null = null;
  let musicFile: File | null = null;
  let phaseText = 'Bereit';

  const rg = ring('var(--sound)', 9);
  const timeEl = h('div', { class: 'time' }, fmtDuration(p.targetMin * 60));
  const phaseEl = h('div', { class: 'phase' }, phaseText);
  const playBtn = h('button', { class: 'play-btn', type: 'button', 'aria-label': 'Start' }, solidIcon('play'));
  const half = Math.pow(2, p.width / 2);
  const viz = spectrumViz({ tinnitusHz: m.freq, notch: mode === 'notched' ? { lo: m.freq / half, hi: m.freq * half } : null });
  const setPhase = (t: string) => { phaseText = t; phaseEl.textContent = t; };

  const updateClock = () => {
    const target = p.targetMin * 60;
    timeEl.textContent = p.targetMin > 0 ? fmtDuration(Math.max(0, target - elapsed)) : fmtDuration(elapsed);
    rg.set(p.targetMin > 0 ? elapsed / target : 0);
  };

  async function start() {
    await engine.ensure();
    try {
      running = starters[mode]();
    } catch {
      return;
    }
    playBtn.replaceChildren(solidIcon('pause'));
    tick = window.setInterval(() => {
      elapsed++;
      updateClock();
      if (p.targetMin > 0 && elapsed >= p.targetMin * 60) finish(true);
    }, 1000);
  }

  function pause() {
    running?.stop();
    running = null;
    if (tick !== null) clearInterval(tick);
    tick = null;
    playBtn.replaceChildren(solidIcon('play'));
    setPhase('Pausiert');
  }

  playBtn.addEventListener('click', () => {
    if (running) return pause();
    if (pre === null) {
      sheet((close) => h('div', null,
        h('p', { class: 'title-l' }, 'Vorher kurz bewerten'),
        h('p', { class: 'body' }, 'Wie laut ist dein Tinnitus jetzt? So sehen wir später, was bei dir wirkt.'),
        scale10(null, (v) => { pre = v; setTimeout(() => { close(); start(); }, 180); }, ['nicht hörbar', 'extrem laut']),
        h('div', { class: 'center mt8' }, btn('Überspringen', () => { pre = -1; close(); start(); }, { variant: 'text' }))));
      return;
    }
    start();
  });

  function finish(auto = false) {
    const wasRunning = !!running;
    pause();
    if (auto) { chime(-30); }
    if (elapsed < 20) { if (!wasRunning) navigate('/therapy'); else toast('Zu kurz zum Speichern', 'info'); return; }
    sheet((close) => h('div', null,
      h('p', { class: 'title-l' }, auto ? 'Sitzung beendet' : 'Sitzung beenden'),
      h('p', { class: 'body' }, `${info.title} · ${fmtDuration(elapsed)} min. Wie laut ist dein Tinnitus jetzt?`),
      scale10(null, (v) => {
        store.update((s) => s.sessions.push({ id: uid(), date: new Date().toISOString(), mode, durationS: elapsed, pre: pre !== null && pre >= 0 ? pre : null, post: v, params: { level: p.level, source: p.source, stimulus: p.stimulus } }));
        close();
        toast(pre !== null && pre >= 0 ? `Gespeichert · ${v - pre <= 0 ? '' : '+'}${v - pre} Punkte` : 'Sitzung gespeichert');
        navigate('/therapy');
      }, ['nicht hörbar', 'extrem laut'])));
  }

  // ---- mode-specific audio
  const starters: Record<TherapyMode, () => Running> = {
    enrichment: () => {
      setPhase(({ am: 'AM-Rauschen 10 Hz', rain: 'Regen', pink: 'Rosa Rauschen', brown: 'Braunes Rauschen' } as Record<string, string>)[p.source] ?? '');
      const v = p.source === 'am' ? playAmNoise(m.freq, m.ear, p.level) : p.source === 'rain' ? playRain(m.ear, p.level) : playNoise(p.source as 'pink' | 'brown', m.ear, p.level);
      return { stop: () => v.stop(400), setLevel: (db) => v.setLevel(db) };
    },
    notched: () => {
      if (p.source === 'music') {
        if (!musicFile) { toast('Bitte zuerst eine Musikdatei wählen', 'info'); throw new Error('no file'); }
        const url = URL.createObjectURL(musicFile);
        const audio = new Audio(url);
        audio.loop = true;
        const node = engine.ctx.createMediaElementSource(audio);
        const v = playNotchedSource(node, m.freq, p.width, m.ear, p.level, () => { audio.pause(); URL.revokeObjectURL(url); });
        audio.play().catch(() => toast('Wiedergabe blockiert', 'alert'));
        setPhase(musicFile.name.replace(/\.[^.]+$/, ''));
        return { stop: () => v.stop(300), setLevel: (db) => v.setLevel(db) };
      }
      setPhase(p.source === 'rain' ? 'Regen mit Lücke' : 'Rauschen mit Lücke');
      const v = p.source === 'rain' ? playNotchedRain(m.freq, p.width, m.ear, p.level) : playNotchedNoise(p.source as 'pink' | 'white' | 'brown', m.freq, p.width, m.ear, p.level);
      return { stop: () => v.stop(300), setLevel: (db) => v.setLevel(db) };
    },
    cr: () => {
      setPhase('4 Töne · 1,5 Hz');
      const c = new CrStimulator({ ft: m.freq, ear: m.ear, levelDb: p.level });
      c.start();
      return { stop: () => c.stop(), setLevel: (db) => c.setLevel(db) };
    },
    reset: () => {
      let alive = true;
      let v: Voice | null = null;
      let level = p.level;
      (async () => {
        let cycle = 0;
        while (alive) {
          cycle++;
          setPhase(`Zyklus ${cycle} · Klang`);
          v = startStimulus(p.stimulus, m.freq, m.ear, level, p.width);
          for (let i = 0; i < p.onS * 10 && alive; i++) await new Promise((r) => setTimeout(r, 100));
          v?.stop(600);
          v = null;
          if (!alive) break;
          setPhase(`Zyklus ${cycle} · Stille – achte auf die Veränderung`);
          for (let i = 0; i < p.offS * 10 && alive; i++) await new Promise((r) => setTimeout(r, 100));
        }
      })();
      return { stop: () => { alive = false; v?.stop(300); }, setLevel: (db) => { level = db; v?.setLevel(db); } };
    },
  };

  // ---- settings
  const lvl = range({ label: 'Pegel', min: -70, max: -8, value: p.level, format: (v) => `${v} dB`, onInput: (v) => { p.level = v; running?.setLevel(v); } });
  const settings: (Node | null)[] = [];
  if (mode === 'enrichment') {
    settings.push(h('p', { class: 'title-m' }, 'Klang'), seg([{ value: 'am', label: 'AM 10 Hz' }, { value: 'rain', label: 'Regen' }, { value: 'pink', label: 'Rosa' }, { value: 'brown', label: 'Braun' }], p.source, (v) => { p.source = v; if (running) { pause(); start(); } }).el,
      h('p', { class: 'small mt8' }, 'Ziel ist der „Mixing Point“: Der Tinnitus soll noch leicht hörbar bleiben, eingebettet in den Klang.'));
  }
  if (mode === 'notched') {
    const file = h('input', { type: 'file', accept: 'audio/*', class: 'hide' }) as HTMLInputElement;
    const fileLbl = h('span', { class: 'small' }, 'Keine Datei');
    const s = seg([{ value: 'pink', label: 'Rosa' }, { value: 'white', label: 'Weiß' }, { value: 'rain', label: 'Regen' }, { value: 'music', label: 'Musik' }], p.source, (v) => { p.source = v; if (v === 'music' && !musicFile) file.click(); else if (running) { pause(); start(); } });
    file.addEventListener('change', () => { musicFile = file.files?.[0] ?? null; if (musicFile) { fileLbl.textContent = musicFile.name; p.source = 'music'; s.set('music'); } });
    const band = h('p', { class: 'small' }, '');
    const setBand = () => { const hh = Math.pow(2, p.width / 2); band.textContent = `Lücke: ${formatHz(m.freq / hh)} – ${formatHz(m.freq * hh)}`; viz.setNotch({ lo: m.freq / hh, hi: m.freq * hh }); };
    setBand();
    settings.push(h('p', { class: 'title-m' }, 'Klangquelle'), s.el, h('div', { class: 'row mt8' }, btn('Musik wählen', () => file.click(), { variant: 'ghost', size: 'sm', icon: 'note' }), fileLbl, file),
      range({ label: 'Breite der Lücke', min: 0.5, max: 2, step: 0.25, value: p.width, format: (v) => `${v} Okt.`, onInput: (v) => { p.width = v; setBand(); }, onChange: () => { if (running) { pause(); start(); } } }).el, band);
  }
  if (mode === 'reset') {
    const sel = h('select') as HTMLSelectElement;
    STIMULI.forEach((s) => sel.appendChild(h('option', { value: s.kind, selected: s.kind === p.stimulus }, `${s.label}${best?.stimulus === s.kind ? ' ★' : ''}`)));
    sel.addEventListener('change', () => (p.stimulus = sel.value as StimulusKind));
    settings.push(
      best ? callout(`Vorausgewählt: dein bester Klang aus dem Labor (Ø −${best.depth.toFixed(1)} Punkte).`, 'good') : callout('Noch kein Labor-Ergebnis, Standard ist Schmalband ⅓ Oktave.', 'warn'),
      h('p', { class: 'title-m' }, 'Klang'), sel,
      range({ label: 'Klang-Phase', min: 15, max: 90, step: 5, value: p.onS, format: (v) => `${v} s`, onInput: (v) => (p.onS = v) }).el,
      range({ label: 'Stille-Phase', min: 15, max: 180, step: 5, value: p.offS, format: (v) => `${v} s`, onInput: (v) => (p.offS = v) }).el);
  }
  if (mode === 'cr') {
    settings.push(h('div', { class: 'row wrap' }, ...CR_RATIOS.map((r) => chip(formatHz(m.freq * r), 'sound'))), h('p', { class: 'small mt8' }, 'Sehr leise, nahe der Hörschwelle, wie in der Originalstudie.'));
  }
  const timerSeg = seg([{ value: '10', label: '10 min' }, { value: '15', label: '15' }, { value: '30', label: '30' }, { value: '60', label: '60' }, { value: '0', label: '∞' }], String(p.targetMin), (v) => { p.targetMin = Number(v); updateClock(); });
  if (![10, 15, 30, 60, 0].includes(p.targetMin)) p.targetMin = 15;
  timerSeg.set(String(p.targetMin));
  updateClock();

  const stopBtn = btn('Beenden', () => finish(false), { variant: 'ghost', size: 'sm', icon: 'stop' });
  root.appendChild(page(
    h('div', { class: 'player' },
      h('p', { class: 'eyebrow', style: 'margin-bottom:2px' }, 'Klang'),
      h('h1', { class: 'title-l' }, info.title),
      evidence(info.level),
      h('div', { class: 'ring-wrap' }, rg.el, h('div', { class: 'ring-center' }, timeEl, phaseEl)),
      playBtn,
      h('div', { class: 'mt16' }, stopBtn)),
    viz.el,
    card('mt16', lvl.el, ...settings, h('p', { class: 'title-m mt16' }, 'Dauer'), timerSeg.el),
    h('details', { class: 'acc' }, h('summary', null, 'Wie es wirken soll und was belegt ist', icon('chevR', 'chev')),
      h('div', { class: 'acc-body prose' }, h('p', null, info.desc), h('p', null, h('b', null, 'Evidenz: '), info.evidence))),
  ));
  // back crumb behaviour: the shell shows no crumb for /therapy, so add one
  const back = btn('Alle Klänge', () => { if (running || elapsed >= 20) finish(false); else navigate('/therapy'); }, { variant: 'text', icon: 'chevL' });
  root.firstElementChild!.prepend(h('div', { style: 'margin:-6px 0 4px -8px' }, back));

  return () => { running?.stop(); if (tick !== null) clearInterval(tick); };
}
