import { h, btn, page, header, card, swap, callout, sectionH, scale10, toast, fmtDuration, fmtDate, chip } from '../ui/dom';
import { icon, solidIcon } from '../ui/icons';
import { ring } from '../ui/chart';
import { store, uid } from '../data/store';
import { engine } from '../audio/engine';
import { chime } from '../audio/synth';
import { navigate, Params } from '../router';
import { LESSONS, TOOLS, Lesson, Tool } from '../data/mindContent';

export function renderMind(root: HTMLElement, params: Params): () => void {
  if (params.lesson) return renderLesson(root, params.lesson);
  if (params.tool === 'thoughts') return renderThoughts(root);
  if (params.tool === 'plan') return renderPlan(root);
  if (params.tool) return renderGuided(root, params.tool);
  const done = store.get().mind.lessonsDone;
  const next = LESSONS.find((l) => !done.includes(l.id));
  const rg = ring('var(--mind)', 12);
  rg.set(done.length / LESSONS.length);
  const nextCard = next
    ? card('glow-mind tap',
        h('p', { class: 'eyebrow c-mind', style: 'margin:0 0 4px' }, `Lektion ${next.n} von ${LESSONS.length}`),
        h('p', { class: 'title-l' }, next.title),
        h('p', { class: 'body', style: 'margin:0 0 14px' }, next.sub),
        btn(`Starten · ${next.minutes} min`, () => navigate(`/mind?lesson=${next.id}`), { variant: 'mind', iconRight: 'chevR' }))
    : card('glow-mind', h('p', { class: 'title-m' }, 'Alle Lektionen abgeschlossen'), h('p', { class: 'body' }, 'Übe weiter mit den Werkzeugen. Wiederholung ist, was wirkt.'));
  nextCard.addEventListener('click', (e) => { if (next && !(e.target as HTMLElement).closest('button')) navigate(`/mind?lesson=${next.id}`); });

  root.appendChild(page(
    h('div', { class: 'row', style: 'align-items:center;gap:16px' },
      h('div', { class: 'grow' }, header('Kopf', 'Kopf-Training', null)),
      h('div', { class: 'ring-wrap', style: 'width:72px;margin:0' }, rg.el, h('div', { class: 'ring-center' }, h('span', { class: 'num', style: 'font-weight:700' }, `${done.length}/8`)))),
    h('p', { class: 'lead' }, 'Kognitive Verhaltenstherapie ist das am besten belegte Verfahren gegen Tinnitus-Belastung (Cochrane 2020, UNITI-Studie 2025). Dieses Programm folgt ihren Bausteinen.'),
    nextCard,
    sectionH('Werkzeuge'),
    h('div', { class: 'grid-2' }, ...TOOLS.map((t) => {
      const c = card('tap flat', h('span', { class: 'li-ico mind' }, icon(t.icon)), h('p', { class: 'title-m mt8', style: 'margin-bottom:0' }, t.title), h('p', { class: 'small', style: 'margin:2px 0 0' }, t.sub));
      c.style.marginBottom = '0';
      c.addEventListener('click', () => navigate(`/mind?tool=${t.id}`));
      return c;
    })),
    sectionH('Alle Lektionen'),
    card(null, h('ul', { class: 'list' }, ...LESSONS.map((l) => {
      const isDone = done.includes(l.id);
      const li = h('li', { style: 'cursor:pointer' },
        h('span', { class: `li-ico ${isDone ? 'done' : 'mind'}` }, isDone ? icon('check') : h('span', { class: 'num', style: 'font-weight:700' }, String(l.n))),
        h('div', { class: 'li-main' }, h('div', { class: 'li-title' }, l.title), h('div', { class: 'li-sub' }, `${l.sub} · ${l.minutes} min`)),
        icon('chevR', 'chev'));
      li.addEventListener('click', () => navigate(`/mind?lesson=${l.id}`));
      return li;
    }))),
  ));
  return () => {};
}

function backLink(): HTMLElement {
  return h('div', { style: 'margin:-6px 0 4px -8px' }, btn('Kopf-Training', () => navigate('/mind'), { variant: 'text', icon: 'chevL' }));
}

/** Minimal markup: blank-line paragraphs, "- " bullet lists, **bold**. */
function prose(text: string): HTMLElement {
  const el = h('div', { class: 'prose' });
  for (const block of text.split(/\n\s*\n/)) {
    const lines = block.trim().split('\n');
    if (lines.every((l) => l.trim().startsWith('- '))) {
      el.appendChild(h('ul', null, ...lines.map((l) => h('li', null, ...inline(l.trim().slice(2))))));
    } else {
      // paragraph possibly followed by bullets
      const para: string[] = [];
      const bullets: string[] = [];
      for (const l of lines) (l.trim().startsWith('- ') ? bullets : para).push(l.trim());
      if (para.length) el.appendChild(h('p', null, ...inline(para.join(' '))));
      if (bullets.length) el.appendChild(h('ul', null, ...bullets.map((b) => h('li', null, ...inline(b.slice(2))))));
    }
  }
  return el;
}

function inline(s: string): (string | Node)[] {
  return s.split(/(\*\*[^*]+\*\*)/).map((part) => (part.startsWith('**') ? h('b', null, part.slice(2, -2)) : part));
}

function logExercise(kind: string, durationS: number): void {
  store.update((d) => d.mind.exercises.push({ id: uid(), date: new Date().toISOString(), kind, durationS }));
}

function renderLesson(root: HTMLElement, id: string): () => void {
  const l = LESSONS.find((x) => x.id === id) as Lesson | undefined;
  if (!l) { navigate('/mind'); return () => {}; }
  const t0 = Date.now();
  const tool = l.tool ? TOOLS.find((t) => t.id === l.tool) : null;
  const reflect = l.reflect ? card(null, h('p', { class: 'title-m' }, 'Zum Nachdenken'), h('p', { class: 'small' }, 'Beantworte die Fragen für dich, gern schriftlich. Nichts davon wird geteilt.'),
    ...l.reflect.map((q) => h('div', { class: 'field' }, h('div', { class: 'field-head' }, h('span', { class: 'lbl' }, q)), h('textarea', { rows: 2, placeholder: 'Deine Antwort …' })))) : null;
  const finish = () => {
    store.update((d) => { if (!d.mind.lessonsDone.includes(l.id)) d.mind.lessonsDone.push(l.id); });
    logExercise(`lesson:${l.id}`, Math.round((Date.now() - t0) / 1000));
    toast(`Lektion ${l.n} abgeschlossen`);
    if (tool) navigate(`/mind?tool=${tool.id}`); else navigate('/mind');
  };
  root.appendChild(page(
    backLink(),
    header(`Lektion ${l.n} von ${LESSONS.length} · ${l.minutes} min`, l.title, l.sub),
    card(null, prose(l.body)),
    reflect,
    tool ? card('glow-mind', h('div', { class: 'row' }, h('span', { class: 'li-ico mind' }, icon(tool.icon)), h('div', { class: 'grow' }, h('p', { class: 'title-m', style: 'margin:0' }, `Übung: ${tool.title}`), h('p', { class: 'small', style: 'margin:0' }, tool.sub)))) : null,
    btn(tool ? 'Abschließen und zur Übung' : 'Lektion abschließen', finish, { variant: 'mind', size: 'lg', block: true, iconRight: 'chevR' }),
  ));
  return () => {};
}

function renderGuided(root: HTMLElement, id: string): () => void {
  const tool = TOOLS.find((t) => t.id === id) as Tool | undefined;
  if (!tool?.steps) { navigate('/mind'); return () => {}; }
  const steps = tool.steps;
  const total = steps.reduce((a, s) => a + s.s, 0);
  let alive = true;
  let running = false;
  let idx = 0;
  let stepLeft = steps[0].s;
  let elapsed = 0;
  let timer: number | null = null;
  const isBreath = tool.id === 'breath';
  const orb = h('div', { class: 'orb' });
  const breathLbl = h('div', { class: 'lbl' }, 'Bereit');
  const rg = ring('var(--mind)', 8);
  const time = h('div', { class: 'time' }, fmtDuration(total));
  const text = h('p', { class: 'title-m center', style: 'min-height:3.2em;max-width:30ch;margin:8px auto 18px' }, steps[0].text);
  const playBtn = h('button', { class: 'play-btn', style: 'background:var(--mind);box-shadow:0 10px 40px color-mix(in srgb,var(--mind) 45%,transparent)' }, solidIcon('play'));

  const visual = isBreath
    ? h('div', { class: 'breath' }, orb, breathLbl)
    : h('div', { class: 'ring-wrap' }, rg.el, h('div', { class: 'ring-center' }, time, h('div', { class: 'phase' }, `Schritt 1 von ${steps.length}`)));

  const applyStep = () => {
    const s = steps[idx];
    text.textContent = s.text;
    if (isBreath) {
      orb.style.transitionDuration = `${s.s}s`;
      orb.style.transform = s.breath === 'in' ? 'scale(1)' : 'scale(0.55)';
      breathLbl.textContent = s.breath === 'in' ? 'Ein' : s.breath === 'out' ? 'Aus' : '';
    } else {
      (visual.querySelector('.phase') as HTMLElement).textContent = `Schritt ${idx + 1} von ${steps.length}`;
      if (idx > 0) chime(-32);
    }
  };

  const loop = () => {
    elapsed++;
    stepLeft--;
    time.textContent = fmtDuration(total - elapsed);
    rg.set(elapsed / total);
    if (stepLeft <= 0) {
      idx++;
      if (idx >= steps.length) return done();
      stepLeft = steps[idx].s;
      applyStep();
    }
  };

  playBtn.addEventListener('click', async () => {
    await engine.ensure();
    if (running) {
      running = false;
      if (timer !== null) clearInterval(timer);
      playBtn.replaceChildren(solidIcon('play'));
      return;
    }
    running = true;
    playBtn.replaceChildren(solidIcon('pause'));
    applyStep();
    timer = window.setInterval(() => alive && loop(), 1000);
  });

  const done = () => {
    if (timer !== null) clearInterval(timer);
    chime(-28);
    logExercise(tool.id, elapsed);
    swap(root.firstElementChild!,
      backLink(),
      card('glow-mind center mt24',
        h('div', { class: 'li-ico done', style: 'margin:0 auto 10px;width:56px;height:56px;border-radius:50%' }, icon('check')),
        h('p', { class: 'title-l' }, 'Gut gemacht'),
        h('p', { class: 'body' }, `${tool.title} · ${fmtDuration(elapsed)} min. Regelmäßigkeit ist wichtiger als Länge.`),
        h('p', { class: 'title-m mt16' }, 'Wie belastend ist der Tinnitus gerade?'),
        scale10(null, (v) => { store.update((d) => d.checkins.push({ id: uid(), ts: new Date().toISOString(), loudness: v, distress: v })); toast('Notiert'); navigate('/mind'); }, ['gar nicht', 'extrem'])),
    );
  };

  root.appendChild(page(
    backLink(),
    h('div', { class: 'player' },
      h('p', { class: 'eyebrow c-mind' }, `Übung · ${tool.minutes} min`),
      h('h1', { class: 'title-l' }, tool.title),
      visual, text, playBtn,
      h('p', { class: 'small mt16' }, isBreath ? 'Im Rhythmus der Kugel atmen: größer werden = einatmen.' : 'Ein leiser Glockenton markiert jeden neuen Schritt. Du kannst die Augen schließen.'))));
  return () => { alive = false; if (timer !== null) clearInterval(timer); };
}

function renderThoughts(root: HTMLElement): () => void {
  const f = { situation: '', thought: '', feeling: -1, alternative: '', feelingAfter: -1 };
  const ta = (ph: string, key: 'situation' | 'thought' | 'alternative') => {
    const t = h('textarea', { rows: 2, placeholder: ph }) as HTMLTextAreaElement;
    t.addEventListener('input', () => (f[key] = t.value));
    return t;
  };
  const list = store.get().mind.thoughts.slice().reverse();
  root.appendChild(page(
    backLink(),
    header('Werkzeug', 'Gedanken-Check', 'Schreib eine Situation auf, in der der Tinnitus dich belastet hat, und prüfe den Gedanken dahinter.'),
    card(null,
      h('p', { class: 'title-m' }, '1 · Situation'), ta('Wo warst du, was war los? z. B. „Abends im Bett, alles still“', 'situation'),
      h('p', { class: 'title-m mt16' }, '2 · Automatischer Gedanke'), ta('Was ging dir durch den Kopf? z. B. „Ich werde heute wieder nicht schlafen“', 'thought'),
      h('p', { class: 'title-m mt16' }, '3 · Wie belastend fühlte sich das an?'), scale10(null, (v) => (f.feeling = v), ['gar nicht', 'extrem'])),
    card('glow-mind',
      h('p', { class: 'title-m' }, '4 · Prüfen'),
      h('ul', { class: 'list' }, ...['Welche Belege sprechen dafür, welche dagegen?', 'Was würde ich einem guten Freund sagen?', 'Wie ist es an einem guten Tag?', 'Was ist realistisch, nicht das Schlimmste?'].map((q) => h('li', null, h('span', { class: 'li-ico mind', style: 'width:28px;height:28px' }, icon('chevR')), h('span', { class: 'li-main', style: 'font-size:15px' }, q)))),
      h('p', { class: 'title-m mt16' }, '5 · Ausgewogenerer Gedanke'), ta('z. B. „Ich habe schon oft trotz Tinnitus geschlafen. Ich mache die Klanganreicherung an.“', 'alternative'),
      h('p', { class: 'title-m mt16' }, '6 · Wie belastend jetzt?'), scale10(null, (v) => (f.feelingAfter = v), ['gar nicht', 'extrem'])),
    btn('Speichern', () => {
      if (!f.thought.trim() || !f.alternative.trim()) { toast('Bitte Gedanke und Alternative ausfüllen', 'info'); return; }
      store.update((d) => d.mind.thoughts.push({ id: uid(), date: new Date().toISOString(), situation: f.situation, thought: f.thought, feeling: Math.max(0, f.feeling), alternative: f.alternative, feelingAfter: Math.max(0, f.feelingAfter) }));
      logExercise('thoughts', 300);
      toast('Gedanken-Check gespeichert');
      navigate('/mind');
    }, { variant: 'mind', size: 'lg', block: true }),
    list.length ? sectionH('Frühere Einträge') : null,
    ...list.slice(0, 10).map((t) => card('tight',
      h('div', { class: 'row between' }, h('span', { class: 'small' }, fmtDate(t.date)), chip(`${t.feeling} → ${t.feelingAfter}`, t.feelingAfter < t.feeling ? 'good' : '')),
      h('p', { class: 'body', style: 'margin:6px 0 2px;text-decoration:line-through;text-decoration-color:var(--text-3)' }, t.thought),
      h('p', { style: 'margin:0;font-weight:600' }, t.alternative))),
  ));
  return () => {};
}

function renderPlan(root: HTMLElement): () => void {
  const tpl = `Was mir kurzfristig hilft:\n- \n\nEin Satz, der mir hilft:\n- „Das war schon öfter so und ist wieder vorbeigegangen.“\n\nWen ich anrufen kann:\n- \n\nWas ich an solchen Tagen bleiben lasse:\n- `;
  const t = h('textarea', { rows: 14, style: 'min-height:320px' }) as HTMLTextAreaElement;
  t.value = store.get().mind.spikePlan || tpl;
  root.appendChild(page(
    backLink(),
    header('Werkzeug', 'Notfallplan', 'Schreib ihn an einem guten Tag. An einem lauten Tag liest du ihn nur noch und folgst ihm.'),
    card(null, t),
    callout('Plötzliche starke Veränderung, pulsierender Tinnitus, Hörverlust oder Schwindel: zeitnah HNO-ärztlich abklären lassen.', 'warn'),
    btn('Speichern', () => { store.update((d) => (d.mind.spikePlan = t.value)); logExercise('plan', 300); toast('Notfallplan gespeichert'); navigate('/mind'); }, { variant: 'mind', size: 'lg', block: true }),
  ));
  return () => {};
}
