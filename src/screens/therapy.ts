import { h, card, note, button, segmented, slider, clear, fmtDuration } from '../ui/dom';
import { store, uid } from '../data/store';
import { engine, formatHz } from '../audio/engine';
import { playNoise, playNotchedNoise, playNotchedSource, playNotchedRain, playRain, Voice } from '../audio/synth';
import { CrStimulator, CR_RATIOS } from '../audio/cr';
import { BimodalStimulator } from '../audio/bimodal';
import { StimulusKind, TherapyMode } from '../data/model';
import { navigate, toast } from '../main';
import { STIMULI, bestRiStimulus, describeStimulus, startStimulus } from './ri';

interface ModeInfo {
  mode: TherapyMode;
  title: string;
  desc: string;
  evidence: string;
  dose: string;
}

const MODES: ModeInfo[] = [
  { mode: 'reset', title: 'Reset-Sitzung (RI-basiert)', desc: 'Dein im Labor wirksamster Klang in Zyklen: Stimulus, Stille, Stimulus. Nutzt Residual Inhibition gezielt, um dem Hörsystem wiederholt Ruhe-Phasen zu geben.', evidence: 'Residual Inhibition ist gut belegt (Roberts 2008, Fournier 2018); langfristige Effekte durch wiederholte RI werden erforscht.', dose: '2–3× täglich 10–15 min' },
  { mode: 'notched', title: 'Notched Sound', desc: 'Rauschen, Regen oder deine eigene Musik mit einer Lücke von einer Oktave um deine Tinnitus-Frequenz. Soll laterale Hemmung im Hörcortex anregen und die Überaktivität bei deiner Frequenz dämpfen.', evidence: 'Tailor-made notched music (Okamoto/Pantev 2010, Stein 2016): kleine, aber signifikante Effekte bei Tinnitus < 8 kHz und längerer Anwendung.', dose: '1–2 h täglich über Monate' },
  { mode: 'cr', title: 'CR-Neuromodulation', desc: 'Vier Töne um deine Tinnitus-Frequenz in zufälliger Reihenfolge, 1,5 Hz Takt, 3 Zyklen an, 2 aus. Ziel ist es, krankhaft synchronisierte Nervenverbände zu „entkoppeln“.', evidence: 'Tass et al. 2012 (RESET-Studie) zeigte deutliche Reduktion; die spätere RESET2-Studie konnte das nicht bestätigen. Evidenz gemischt.', dose: '4–6 h täglich in der Original-Studie, hier flexibel' },
  { mode: 'enrichment', title: 'Klanganreicherung', desc: 'Leises, angenehmes Hintergrundrauschen knapp unter der Maskierungsschwelle („Mixing Point“). Reduziert den Kontrast zwischen Tinnitus und Stille und unterstützt die Habituation.', evidence: 'Kernbestandteil der Tinnitus-Retraining-Therapie; gut belegt für Belastungsreduktion.', dose: 'So lange wie angenehm, besonders beim Einschlafen' },
  { mode: 'bimodal', title: 'Bimodal (experimentell)', desc: 'Kurze Klangimpulse auf deiner Frequenz, gekoppelt mit Vibrationsimpulsen des Geräts. Angelehnt an auditorisch-somatosensorische Protokolle, aber ohne deren präzise elektrische Stimulation.', evidence: 'Bimodale Stimulation (Shore 2023, Lenire) zeigt in Studien starke Effekte, mit spezieller Hardware. Diese Nachbildung ist unerprobt.', dose: '30 min täglich' },
];

export function renderTherapy(root: HTMLElement): () => void {
  const match = store.latestMatch();
  root.appendChild(h('h1', null, 'Therapie'));
  if (!match) {
    root.appendChild(card(null, note('Zuerst brauchen wir deine Tinnitus-Frequenz.', 'warn'), h('p', null, button('Zum Matching →', () => navigate('/match'), 'btn'))));
    return () => {};
  }

  let active: TherapyMode | null = null;
  const panel = h('div');
  root.appendChild(panel);
  let stopFn: (() => void) | null = null;
  let timer: number | null = null;
  let seconds = 0;
  let preRating: number | null = null;

  function renderMenu() {
    clear(panel);
    const best = bestRiStimulus(store.get().riTrials);
    panel.append(h('p', { class: 'muted' }, `Tinnitus-Frequenz ${formatHz(match!.freq)} · ${best ? `Bester RI-Klang: ${describeStimulus(best.stimulus)}` : 'RI-Labor noch nicht abgeschlossen'}`));
    for (const m of MODES) {
      panel.append(card(null, h('div', { class: 'mode-card', on: { click: () => openMode(m.mode) } },
        h('div', { class: 'title' }, m.title),
        h('div', { class: 'desc' }, m.desc),
        h('div', { class: 'evidence muted' }, 'Evidenz: ' + m.evidence),
        h('p', null, h('span', { class: 'pill' }, m.dose), ' ', button('Starten', () => openMode(m.mode), 'btn small')),
      )));
    }
  }

  function openMode(mode: TherapyMode) {
    active = mode;
    seconds = 0;
    preRating = null;
    renderMode();
  }

  function ratingRow(onPick: (v: number) => void, value: number | null) {
    const row = h('div', { class: 'rating' });
    for (let i = 0; i <= 10; i++) {
      const b = button(String(i), () => { row.querySelectorAll('button').forEach((x) => x.classList.remove('active')); b.classList.add('active'); onPick(i); }, '');
      if (value === i) b.classList.add('active');
      row.appendChild(b);
    }
    return row;
  }

  function renderMode() {
    clear(panel);
    const info = MODES.find((m) => m.mode === active)!;
    const clock = h('div', { class: 'timer' }, '0:00');
    const controls = h('div');
    const params: Record<string, number | string | boolean> = {};
    const startBtn = button('▶ Sitzung starten', async () => {
      await engine.ensure();
      if (stopFn) return;
      stopFn = await starters[active!](controls, params);
      startBtn.disabled = true;
      stopBtn.disabled = false;
      clock.classList.add('pulse');
      timer = window.setInterval(() => { seconds++; clock.textContent = fmtDuration(seconds); }, 1000);
    }, 'btn big');
    const stopBtn = button('■ Beenden & speichern', () => endSession(), 'btn secondary');
    stopBtn.disabled = true;

    panel.append(
      h('p', null, button('← Alle Modi', () => { if (stopFn) endSession(); else renderMenu(); }, 'btn ghost small')),
      card(info.title, h('p', { class: 'muted' }, info.desc),
        h('h3', null, 'Vorher: Wie laut ist dein Tinnitus jetzt? (0–10)'), ratingRow((v) => (preRating = v), preRating),
        controls, clock, h('div', { class: 'row' }, startBtn, stopBtn)),
    );
    builders[active!](controls, params);
  }

  function endSession() {
    if (timer !== null) window.clearInterval(timer);
    timer = null;
    stopFn?.();
    stopFn = null;
    const dur = seconds;
    const mode = active!;
    clear(panel);
    let post: number | null = null;
    panel.append(card('Sitzung beendet',
      h('p', null, `${MODES.find((m) => m.mode === mode)!.title} · ${fmtDuration(dur)} min`),
      h('h3', null, 'Nachher: Wie laut ist dein Tinnitus jetzt? (0–10)'), ratingRow((v) => (post = v), null),
      h('p', { style: 'margin-top:12px' }, button('Speichern', () => {
        store.update((d) => d.sessions.push({ id: uid(), date: new Date().toISOString(), mode, durationS: dur, pre: preRating, post, params: {} }));
        toast('Sitzung gespeichert');
        renderMenu();
      }, 'btn big')),
      h('p', null, button('Verwerfen', () => renderMenu(), 'btn ghost small')),
    ));
  }

  // --------- Mode builders: build controls; starters: start audio and return stop fn ----------
  type Builder = (host: HTMLElement, p: Record<string, number | string | boolean>) => void;
  type Starter = (host: HTMLElement, p: Record<string, number | string | boolean>) => Promise<() => void>;

  const levelSlider = (p: Record<string, number | string | boolean>, def: number, label = 'Pegel', onLive?: (v: number) => void) => {
    p.level = def;
    return slider({ min: -60, max: -6, step: 1, value: def, label, format: (v) => `${v} dB`, onInput: (v) => { p.level = v; onLive?.(v); } }).el;
  };

  let liveVoice: Voice | null = null;
  let liveCr: CrStimulator | null = null;
  let liveBimodal: BimodalStimulator | null = null;
  const setLive = (v: number) => { liveVoice?.setLevel(v); liveCr?.setLevel(v); liveBimodal?.setLevel(v); };

  const builders: Record<TherapyMode, Builder> = {
    notched(host, p) {
      p.source = 'pink';
      p.width = store.get().settings.notchWidthOctaves;
      const fileInfo = h('p', { class: 'muted' }, 'Keine Datei gewählt');
      const file = h('input', { type: 'file', accept: 'audio/*', style: 'display:none' }) as HTMLInputElement;
      file.addEventListener('change', () => {
        const f = file.files?.[0];
        if (!f) return;
        musicFile = f;
        fileInfo.textContent = `Datei: ${f.name}`;
        p.source = 'music';
        srcSeg.set('music');
      });
      const srcSeg = segmented([{ value: 'pink', label: 'Rosa Rauschen' }, { value: 'white', label: 'Weißes Rauschen' }, { value: 'brown', label: 'Braunes Rauschen' }, { value: 'rain', label: 'Regen' }, { value: 'music', label: 'Eigene Musik' }], 'pink', (v) => {
        p.source = v;
        if (v === 'music' && !musicFile) file.click();
      });
      const half = Math.pow(2, Number(p.width) / 2);
      const bandInfo = h('p', { class: 'muted' }, `Notch: ${formatHz(match!.freq / half)} – ${formatHz(match!.freq * half)}`);
      host.append(
        h('h3', null, 'Klangquelle'), srcSeg.el, h('p', null, button('Musikdatei wählen', () => file.click(), 'btn secondary small'), file), fileInfo,
        slider({ min: 0.5, max: 2, step: 0.25, value: Number(p.width), label: 'Notch-Breite (Oktaven)', format: (v) => `${v}`, onInput: (v) => { p.width = v; const hh = Math.pow(2, v / 2); bandInfo.textContent = `Notch: ${formatHz(match!.freq / hh)} – ${formatHz(match!.freq * hh)}`; } }).el,
        bandInfo,
        levelSlider(p, -24, 'Pegel (angenehm, nicht laut)', setLive),
        note('Bei eigener Musik: Stücke mit viel Hochton-Anteil (Akustikgitarre, Streicher, Becken) wirken besser als Bass-lastige. Die Notch-Lücke muss im Hörbereich liegen, bei starkem Hörverlust auf deiner Frequenz ist der Effekt geringer.'),
      );
    },
    cr(host, p) {
      const freqs = CR_RATIOS.map((r) => match!.freq * r);
      host.append(
        h('p', null, 'Stimulationstöne: ', ...freqs.map((f) => h('span', { class: 'pill accent', style: 'margin-right:6px' }, formatHz(f)))),
        levelSlider(p, -30, 'Pegel (knapp über der Hörschwelle, leise)', setLive),
        note('In der Originalstudie wurde CR-Stimulation sehr leise, nahe der Hörschwelle, über viele Stunden täglich angewendet. Leise ist hier wichtiger als laut.'),
      );
    },
    reset(host, p) {
      const best = bestRiStimulus(store.get().riTrials);
      p.stimulus = best?.stimulus ?? 'nbn-third';
      p.onS = 30;
      p.offS = 60;
      p.level = Math.min(-6, (match!.mmlDb ?? match!.loudnessDb) + 10);
      const seg = segmented(STIMULI.map((s) => ({ value: s.kind, label: s.label })), p.stimulus as StimulusKind, (v) => (p.stimulus = v));
      const status = h('div', { class: 'big-number', style: 'font-size:22px' }, 'Bereit');
      host.append(
        best ? note(`Vorausgewählt: dein bester RI-Klang (${describeStimulus(best.stimulus)}, Ø Unterdrückung ${best.depth.toFixed(1)}).`, 'ok') : note('Kein RI-Ergebnis vorhanden, Standard ist Schmalband ⅓ Oktave. Teste im RI-Labor, welcher Klang bei dir am besten wirkt.', 'warn'),
        h('h3', null, 'Stimulus'), seg.el,
        slider({ min: 15, max: 90, step: 5, value: 30, label: 'Stimulus-Dauer', format: (v) => `${v} s`, onInput: (v) => (p.onS = v) }).el,
        slider({ min: 15, max: 180, step: 5, value: 60, label: 'Stille danach', format: (v) => `${v} s`, onInput: (v) => (p.offS = v) }).el,
        slider({ min: -60, max: -6, step: 1, value: Number(p.level), label: 'Pegel', format: (v) => `${v} dB`, onInput: (v) => { p.level = v; setLive(v); } }).el,
        status,
      );
      status.id = 'reset-status';
    },
    enrichment(host, p) {
      p.source = 'rain';
      const def = match!.mmlDb !== null ? Math.min(-6, match!.mmlDb - 6) : -36;
      host.append(
        h('h3', null, 'Klang'),
        segmented([{ value: 'rain', label: 'Regen' }, { value: 'pink', label: 'Rosa Rauschen' }, { value: 'brown', label: 'Braunes Rauschen' }, { value: 'white', label: 'Weißes Rauschen' }, { value: 'notched', label: 'Notched Rosa' }], 'rain', (v) => (p.source = v)).el,
        levelSlider(p, def, 'Pegel („Mixing Point“: Tinnitus noch leicht hörbar)', setLive),
        note('Ziel ist nicht, den Tinnitus zu verdecken, sondern ihn in einen angenehmen Klang einzubetten. Der Pegel sollte so sein, dass du beides hörst.'),
      );
    },
    bimodal(host, p) {
      p.interval = 1000;
      host.append(
        BimodalStimulator.vibrationSupported ? note('Vibration wird von diesem Gerät unterstützt. Halte das Telefon in der Hand oder lege es an Nacken/Kiefer.', 'ok') : note('Dieses Gerät/dieser Browser unterstützt keine Vibration (iOS Safari z. B. nicht). Der Modus läuft dann als reine Klang-Impuls-Stimulation.', 'warn'),
        slider({ min: 500, max: 2000, step: 100, value: 1000, label: 'Impuls-Abstand', format: (v) => `${v} ms`, onInput: (v) => (p.interval = v) }).el,
        levelSlider(p, -30, 'Pegel', setLive),
      );
    },
  };

  let musicFile: File | null = null;
  let audioEl: HTMLAudioElement | null = null;

  const starters: Record<TherapyMode, Starter> = {
    async notched(_host, p) {
      const width = Number(p.width);
      const level = Number(p.level);
      const src = String(p.source);
      if (src === 'music') {
        if (!musicFile) { toast('Bitte zuerst Musikdatei wählen'); return () => {}; }
        const url = URL.createObjectURL(musicFile);
        audioEl = new Audio(url);
        audioEl.loop = true;
        audioEl.crossOrigin = 'anonymous';
        const node = engine.ctx.createMediaElementSource(audioEl);
        liveVoice = playNotchedSource(node, match!.freq, width, match!.ear, level, () => { audioEl?.pause(); URL.revokeObjectURL(url); audioEl = null; });
        await audioEl.play().catch(() => toast('Wiedergabe blockiert, bitte erneut starten'));
        return () => { liveVoice?.stop(); liveVoice = null; };
      }
      if (src === 'rain') {
        liveVoice = playNotchedRain(match!.freq, width, match!.ear, level);
        return () => { liveVoice?.stop(); liveVoice = null; };
      }
      liveVoice = playNotchedNoise(src as 'pink' | 'white' | 'brown', match!.freq, width, match!.ear, level);
      return () => { liveVoice?.stop(); liveVoice = null; };
    },
    async cr(_host, p) {
      liveCr = new CrStimulator({ ft: match!.freq, ear: match!.ear, levelDb: Number(p.level) });
      liveCr.start();
      return () => { liveCr?.stop(); liveCr = null; };
    },
    async reset(_host, p) {
      const status = document.getElementById('reset-status');
      let running = true;
      let cycle = 0;
      const loop = async () => {
        while (running) {
          cycle++;
          if (status) status.textContent = `Zyklus ${cycle}: Klang (${p.onS} s)`;
          liveVoice = startStimulus(p.stimulus as StimulusKind, match!.freq, match!.ear, Number(p.level), store.get().settings.notchWidthOctaves);
          await wait(Number(p.onS) * 1000, () => running);
          liveVoice?.stop(100);
          liveVoice = null;
          if (!running) break;
          if (status) status.textContent = `Zyklus ${cycle}: Stille, auf den Tinnitus achten (${p.offS} s)`;
          await wait(Number(p.offS) * 1000, () => running);
        }
        if (status) status.textContent = 'Beendet';
      };
      loop();
      return () => { running = false; liveVoice?.stop(); liveVoice = null; };
    },
    async enrichment(_host, p) {
      const src = String(p.source);
      const level = Number(p.level);
      if (src === 'rain') liveVoice = playRain(match!.ear, level);
      else if (src === 'notched') liveVoice = playNotchedNoise('pink', match!.freq, store.get().settings.notchWidthOctaves, match!.ear, level);
      else liveVoice = playNoise(src as 'pink' | 'white' | 'brown', match!.ear, level);
      return () => { liveVoice?.stop(); liveVoice = null; };
    },
    async bimodal(_host, p) {
      liveBimodal = new BimodalStimulator(match!.freq, match!.ear, Number(p.level), Number(p.interval));
      liveBimodal.start();
      return () => { liveBimodal?.stop(); liveBimodal = null; };
    },
  };

  function wait(ms: number, alive: () => boolean): Promise<void> {
    return new Promise((res) => {
      const t0 = Date.now();
      const id = window.setInterval(() => {
        if (!alive() || Date.now() - t0 >= ms) { window.clearInterval(id); res(); }
      }, 100);
    });
  }

  renderMenu();
  return () => {
    if (timer !== null) window.clearInterval(timer);
    stopFn?.();
    stopFn = null;
    liveVoice?.stop();
    liveCr?.stop();
    liveBimodal?.stop();
  };
}
