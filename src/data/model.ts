export type Ear = 'left' | 'right' | 'both';

export interface HearingPoint {
  freq: number;
  /** Relative threshold in dB (0 = app full scale; more negative = better hearing) */
  level: number;
}

export interface HearingTest {
  id: string;
  date: string;
  left: HearingPoint[];
  right: HearingPoint[];
}

/** Likeness-rating tinnitus spectrum (Noreña et al. 2002). */
export interface TinnitusSpectrum {
  id: string;
  date: string;
  ear: Ear;
  timbre: 'tone' | 'hiss';
  points: { freq: number; value: number }[]; // mean likeness 0–10
  peak: number;
}

export interface TinnitusMatch {
  id: string;
  date: string;
  ear: Ear;
  freq: number;
  trials: number[];
  spreadOctaves: number;
  loudnessDb: number;
  timbre: 'tone' | 'hiss';
  mmlDb: number | null;
}

export type StimulusKind = 'tone' | 'am-tone' | 'nbn-third' | 'nbn-octave' | 'bbn' | 'notched-bbn';

export interface ResidualInhibitionTrial {
  id: string;
  date: string;
  stimulus: StimulusKind;
  blind: boolean;
  centerFreq: number;
  levelDb: number;
  durationS: number;
  /** Loudness ratings (0–10) sampled every 2 s after stimulus offset */
  curve: number[];
  baseline: number;
  depth: number;
  durationOfEffectS: number;
}

export type SomaticManeuver = 'clench' | 'jaw-forward' | 'jaw-open' | 'head-forward' | 'head-back' | 'head-left' | 'head-right' | 'gaze';

export interface SomaticTest {
  id: string;
  date: string;
  results: { maneuver: SomaticManeuver; change: -1 | 0 | 1 | 2 }[]; // -1 quieter, 0 none, 1 louder, 2 pitch/timbre change
  somatic: boolean;
}

export type TherapyMode = 'reset' | 'notched' | 'enrichment' | 'cr';

export interface TherapySession {
  id: string;
  date: string;
  mode: TherapyMode;
  durationS: number;
  pre: number | null;
  post: number | null;
  params: Record<string, number | string | boolean>;
}

/** Ecological momentary assessment: quick in-the-moment rating. */
export interface CheckIn {
  id: string;
  ts: string;
  loudness: number; // 0–10
  distress: number; // 0–10
}

export interface JournalEntry {
  id: string;
  date: string; // YYYY-MM-DD
  loudness: number;
  distress: number;
  sleep: number;
  stress: number;
  noiseExposure: boolean;
  caffeine: boolean;
  alcohol: boolean;
  notes: string;
}

export interface WeeklyCheck {
  id: string;
  date: string;
  answers: number[];
  score: number;
}

export interface ThoughtRecord {
  id: string;
  date: string;
  situation: string;
  thought: string;
  feeling: number; // 0–10 distress
  alternative: string;
  feelingAfter: number;
}

export interface MindProgress {
  lessonsDone: string[];
  exercises: { id: string; date: string; kind: string; durationS: number }[];
  thoughts: ThoughtRecord[];
  spikePlan: string;
}

export interface Settings {
  masterVolume: number;
  preferredEar: Ear;
  notchWidthOctaves: number;
  dailyGoalMin: number;
  name: string;
  onboarded: boolean;
  headphonesOk: boolean;
  programStart: string | null; // ISO date
  blindRi: boolean;
}

export interface AppData {
  version: 2;
  settings: Settings;
  hearingTests: HearingTest[];
  spectra: TinnitusSpectrum[];
  matches: TinnitusMatch[];
  riTrials: ResidualInhibitionTrial[];
  somatic: SomaticTest[];
  sessions: TherapySession[];
  checkins: CheckIn[];
  journal: JournalEntry[];
  weekly: WeeklyCheck[];
  mind: MindProgress;
}

export const defaultSettings: Settings = {
  masterVolume: 0.5,
  preferredEar: 'both',
  notchWidthOctaves: 1,
  dailyGoalMin: 60,
  name: '',
  onboarded: false,
  headphonesOk: false,
  programStart: null,
  blindRi: true,
};

export function emptyData(): AppData {
  return {
    version: 2,
    settings: { ...defaultSettings },
    hearingTests: [],
    spectra: [],
    matches: [],
    riTrials: [],
    somatic: [],
    sessions: [],
    checkins: [],
    journal: [],
    weekly: [],
    mind: { lessonsDone: [], exercises: [], thoughts: [], spikePlan: '' },
  };
}
