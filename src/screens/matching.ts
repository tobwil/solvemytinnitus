import { h, card, note, button, segmented, slider, clear, geoMedian } from '../ui/dom';
import { store, uid } from '../data/store';
import { engine, formatHz, octaveDistance } from '../audio/engine';
import { playTone, playNarrowbandNoise, playNoise, Voice } from '../audio/synth';
import { Ear } from '../data/model';
import { navigate, toast } from '../main';

type Step = 'setup' | 'coarse' | 'fine' | 'loudness' | 'mml' | 'done';

const F_MIN = 500;
const F_MAX = 18000;
const LEVEL_MATCH = -30;

export function renderMatching(root: HTMLElement): () => void {
  let step: Step = 'setup';
  let ear: Ear = store.get().settings.preferredEar;
  let timbre: 'tone' | 'hiss' = 'tone';
  let freq = 8000;
  let trials: number[] = [];
  let loudnessDb = LEVEL_MATCH;
  let mmlDb: number | null = null;
  let voice: (Voice & { setFreq(f: number): void }) | null = null;
  let noiseVoice: Voice | null = null;
  let playing = false;

  root.appendChild(h('h1', null, 'Tinnitus-Matching'));
  const panel = h('div');
  root.appendChild(panel);

  const toSlider = (f: number) => Math.log2(f / F_MIN) / Math.log2(F_MAX / F_MIN) * 1000;
  const fromSlider = (v: number) => F_MIN * Math.pow(F_MAX / F_MIN, v / 1000);

  function stopAll() {
    voice?.stop(30);
    voice = null;
    noiseVoice?.stop(30);
    noiseVoice = null;
    playing = false;
  }

  async function startVoice(db = LEVEL_MATCH) {
    await engine.ensure();
    voice?.stop(10);
    voice = timbre === 'tone' ? playTone(freq, ear, db) : playNarrowbandNoise(freq, 1 / 3, ear, db);
    playing = true;
  }

  function render() {
    clear(panel);
    switch (step) {
      case 'setup': return renderSetup();
      case 'coarse': return renderCoarse();
      case 'fine': return renderFine();
      case 'loudness': return renderLoudness();
      case 'mml': return renderMml();
      case 'done': return renderDone();
    }
  }

  function renderSetup() {
    panel.append(
      card('Vorbereitung',
        h('ol', { class: 'steps' },
          h('li', null, 'Kopfhörer aufsetzen, ruhige Umgebung, Lautstärke oben auf ca. 50 %.'),
          h('li', null, 'Konzentriere dich 10 Sekunden auf deinen Tinnitus: Ist er eher ein reiner Pfeifton oder ein Zischen/Rauschen? Ist er auf einem Ohr lauter?'),
          h('li', null, 'Du wirst den Vergleichston dreimal unabhängig einstellen. Daraus bilden wir den Median und sehen, wie stabil dein Matching ist.'),
        ),
        h('h3', null, 'Welches Ohr?'),
        segmented<Ear>([{ value: 'left', label: 'Links' }, { value: 'right', label: 'Rechts' }, { value: 'both', label: 'Beide' }], ear, (v) => (ear = v)).el,
        h('h3', null, 'Klangfarbe'),
        segmented<'tone' | 'hiss'>([{ value: 'tone', label: 'Reiner Ton (Pfeifen)' }, { value: 'hiss', label: 'Zischen (Schmalband-Rauschen)' }], timbre, (v) => (timbre = v)).el,
        h('p', { style: 'margin-top:14px' }, button('Weiter →', () => { step = 'coarse'; render(); }, 'btn big')),
      ),
      note('Tipp: Die meisten konzertinduzierten Tinnitus liegen zwischen 6 und 12 kHz. Bei sehr hohen Frequenzen (>12 kHz) brauchst du gute Kopfhörer, Billig-Ohrhörer geben dort kaum noch etwas wieder.'),
    );
  }

  function renderCoarse() {
    const trialNo = trials.length + 1;
    // Start each trial from a randomised position so the three trials are independent
    if (trials.length) freq = Math.min(F_MAX, Math.max(F_MIN, trials[trials.length - 1] * Math.pow(2, (Math.random() - 0.5) * 1.0)));
    const freqDisplay = h('div', { class: 'big-number' }, formatHz(freq));
    const sl = slider({
      min: 0, max: 1000, step: 1, value: toSlider(freq), label: 'Frequenz grob',
      format: (v) => formatHz(fromSlider(v)),
      onInput: (v) => { freq = fromSlider(v); freqDisplay.textContent = formatHz(freq); voice?.setFreq(freq); },
    });
    const playBtn = button(playing ? '■ Stopp' : '▶ Vergleichston abspielen', async () => {
      if (playing) { stopAll(); playBtn.textContent = '▶ Vergleichston abspielen'; } else { await startVoice(); playBtn.textContent = '■ Stopp'; }
    }, 'btn');
    const fine = (semis: number) => {
      freq = Math.min(F_MAX, Math.max(F_MIN, freq * Math.pow(2, semis / 12)));
      sl.set(toSlider(freq));
      freqDisplay.textContent = formatHz(freq);
      voice?.setFreq(freq);
    };
    panel.append(
      card(`Durchgang ${trialNo} von 3 · Grob-Matching`,
        h('p', { class: 'muted' }, 'Spiele den Vergleichston ab und schiebe den Regler, bis die Tonhöhe deinem Tinnitus am nächsten kommt. Danach mit den Tasten fein nachjustieren.'),
        freqDisplay, sl.el,
        h('div', { class: 'row' },
          button('−1 Halbton', () => fine(-1), 'btn secondary small'),
          button('−¼', () => fine(-0.25), 'btn secondary small'),
          button('+¼', () => fine(0.25), 'btn secondary small'),
          button('+1 Halbton', () => fine(1), 'btn secondary small'),
        ),
        h('p', null, playBtn),
        h('p', null, button('Passt, Oktave prüfen →', () => { stopAll(); step = 'fine'; render(); }, 'btn big')),
      ),
    );
  }

  function renderFine() {
    // Octave confusion check: play f/2, f, 2f and let the user choose
    const candidates = [freq / 2, freq, freq * 2].filter((f) => f >= F_MIN && f <= F_MAX);
    const info = h('p', { class: 'muted' }, 'Beim Pitch-Matching wird häufig die Oktave verwechselt. Höre die Varianten nacheinander an und wähle die, die deinem Tinnitus wirklich entspricht.');
    const list = h('div', { class: 'grid2' });
    for (const f of candidates) {
      const isCur = Math.abs(f - freq) < 1;
      const c = h('div', { class: 'stat' },
        h('div', { class: 'label' }, isCur ? 'Deine Einstellung' : f < freq ? 'Eine Oktave tiefer' : 'Eine Oktave höher'),
        h('div', { class: 'value' }, formatHz(f)),
        h('div', { class: 'row', style: 'margin-top:8px' },
          button('▶ Anhören', async () => { freq = f; await startVoice(); setTimeout(() => stopAll(), 1500); }, 'btn small secondary'),
          button('Das ist er', () => { freq = f; stopAll(); recordTrial(); }, 'btn small'),
        ));
      list.appendChild(c);
    }
    panel.append(card('Oktaven-Check', info, list, h('p', { style: 'margin-top:12px' }, button('← Zurück zum Regler', () => { step = 'coarse'; render(); }, 'btn ghost small'))));
  }

  function recordTrial() {
    trials.push(freq);
    if (trials.length < 3) {
      toast(`Durchgang ${trials.length} gespeichert: ${formatHz(freq)}`);
      step = 'coarse';
    } else {
      freq = geoMedian(trials);
      step = 'loudness';
    }
    render();
  }

  function renderLoudness() {
    const spread = Math.max(...trials.map((t) => octaveDistance(t, freq)));
    const lvl = slider({
      min: -70, max: -6, step: 1, value: loudnessDb, label: 'Pegel des Vergleichstons', format: (v) => `${v} dB`,
      onInput: (v) => { loudnessDb = v; voice?.setLevel(v); },
    });
    const playBtn = button('▶ Ton abspielen', async () => {
      if (playing) { stopAll(); playBtn.textContent = '▶ Ton abspielen'; } else { await startVoice(loudnessDb); playBtn.textContent = '■ Stopp'; }
    }, 'btn');
    panel.append(
      card('Ergebnis der drei Durchgänge',
        h('div', { class: 'big-number' }, formatHz(freq), h('small', null, 'Median')),
        h('p', { class: 'muted' }, `Einzelwerte: ${trials.map(formatHz).join(' · ')} · größte Abweichung ${(spread * 12).toFixed(1)} Halbtöne`),
        spread > 0.5 ? note('Die Durchgänge streuen stark (mehr als eine halbe Oktave). Das ist bei hochfrequentem Tinnitus normal, wiederhole das Matching an einem anderen Tag, der Median wird dann stabiler.', 'warn') : note('Gute Übereinstimmung der Durchgänge.', 'ok'),
      ),
      card('Lautheits-Matching',
        h('p', { class: 'muted' }, 'Stelle den Pegel so ein, dass der Vergleichston genauso laut erscheint wie dein Tinnitus.'),
        lvl.el, h('p', null, playBtn),
        h('p', null, button('Gleich laut →', () => { stopAll(); step = 'mml'; render(); }, 'btn big')),
      ),
    );
  }

  function renderMml() {
    let db = -40;
    const lvl = slider({
      min: -70, max: -6, step: 1, value: db, label: 'Pegel Breitbandrauschen', format: (v) => `${v} dB`,
      onInput: (v) => { db = v; noiseVoice?.setLevel(v); },
    });
    const playBtn = button('▶ Rauschen abspielen', async () => {
      await engine.ensure();
      if (noiseVoice) { noiseVoice.stop(); noiseVoice = null; playBtn.textContent = '▶ Rauschen abspielen'; } else { noiseVoice = playNoise('white', ear, db); playBtn.textContent = '■ Stopp'; }
    }, 'btn');
    panel.append(
      card('Minimale Maskierungsschwelle (MML)',
        h('p', { class: 'muted' }, 'Erhöhe das Rauschen langsam, bis du deinen Tinnitus gerade nicht mehr wahrnimmst. Die MML sagt voraus, wie gut Klangtherapien bei dir anschlagen und legt den Pegel für die Residual-Inhibition-Tests fest.'),
        lvl.el, h('p', null, playBtn),
        h('div', { class: 'row' },
          button('Tinnitus ist gerade verdeckt →', () => { mmlDb = db; stopAll(); finish(); }, 'btn big'),
          button('Überspringen', () => { mmlDb = null; stopAll(); finish(); }, 'btn secondary'),
        ),
      ),
    );
  }

  function finish() {
    const spread = Math.max(...trials.map((t) => octaveDistance(t, freq)));
    store.update((d) => {
      d.matches.push({ id: uid(), date: new Date().toISOString(), ear, freq: Math.round(freq), trials: trials.map(Math.round), spreadOctaves: spread, loudnessDb, timbre, mmlDb });
      d.settings.preferredEar = ear;
    });
    step = 'done';
    render();
  }

  function renderDone() {
    const m = store.latestMatch()!;
    panel.append(
      card('Matching gespeichert',
        h('div', { class: 'big-number' }, formatHz(m.freq)),
        h('div', { class: 'grid2' },
          h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Ohr'), h('div', { class: 'value' }, m.ear === 'both' ? 'Beide' : m.ear === 'left' ? 'Links' : 'Rechts')),
          h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Klangfarbe'), h('div', { class: 'value' }, m.timbre === 'tone' ? 'Ton' : 'Zischen')),
          h('div', { class: 'stat' }, h('div', { class: 'label' }, 'Lautheit'), h('div', { class: 'value' }, `${m.loudnessDb} dB`)),
          h('div', { class: 'stat' }, h('div', { class: 'label' }, 'MML'), h('div', { class: 'value' }, m.mmlDb === null ? '—' : `${m.mmlDb} dB`)),
        ),
        h('p', { style: 'margin-top:12px' }, button('Weiter ins RI-Labor →', () => navigate('/ri'), 'btn big')),
        h('p', null, button('Anderes Ohr matchen', () => { trials = []; step = 'setup'; render(); }, 'btn secondary')),
      ),
    );
  }

  render();
  return () => stopAll();
}
