export type Ear = 'left' | 'right' | 'both';

export interface HearingPoint {
  freq: number;
  /** Relative threshold in dB (0 = loudest reference level of the app, more negative = better hearing) */
  level: number;
}

export interface HearingTest {
  id: string;
  date: string;
  left: HearingPoint[];
  right: HearingPoint[];
}

export interface TinnitusMatch {
  id: string;
  date: string;
  ear: Ear;
  /** Matched tinnitus frequency in Hz (median of trials) */
  freq: number;
  /** Individual trial values in Hz */
  trials: number[];
  /** Spread of trials as fraction of an octave */
  spreadOctaves: number;
  /** Loudness match in dB relative to app reference */
  loudnessDb: number;
  /** Timbre: pure tone or hiss (narrowband noise) */
  timbre: 'tone' | 'hiss';
  /** Minimum masking level with broadband noise, dB relative */
  mmlDb: number | null;
}

export type StimulusKind = 'tone' | 'nbn-third' | 'nbn-octave' | 'bbn' | 'notched-bbn';

export interface ResidualInhibitionTrial {
  id: string;
  date: string;
  stimulus: StimulusKind;
  centerFreq: number;
  levelDb: number;
  durationS: number;
  /** Loudness ratings (0-10) sampled every 2 s after stimulus ends */
  curve: number[];
  baseline: number;
  /** Max suppression in points (baseline - min) */
  depth: number;
  /** Seconds until loudness returned to >= 90 % of baseline (or full window) */
  durationOfEffectS: number;
}

export type TherapyMode = 'notched' | 'cr' | 'enrichment' | 'reset' | 'bimodal';

export interface TherapySession {
  id: string;
  date: string;
  mode: TherapyMode;
  durationS: number;
  pre: number | null;
  post: number | null;
  params: Record<string, number | string | boolean>;
}

export interface JournalEntry {
  id: string;
  date: string; // YYYY-MM-DD
  loudness: number; // 0-10
  distress: number; // 0-10
  sleep: number; // 0-10 quality
  stress: number; // 0-10
  noiseExposure: boolean;
  caffeine: boolean;
  alcohol: boolean;
  notes: string;
}

export interface WeeklyCheck {
  id: string;
  date: string;
  answers: number[]; // 0-4 each
  score: number; // 0-100
}

export interface Settings {
  masterVolume: number; // 0..1
  preferredEar: Ear;
  notchWidthOctaves: number; // default 1
  dailyGoalMin: number;
  name: string;
}

export interface AppData {
  version: 1;
  settings: Settings;
  hearingTests: HearingTest[];
  matches: TinnitusMatch[];
  riTrials: ResidualInhibitionTrial[];
  sessions: TherapySession[];
  journal: JournalEntry[];
  weekly: WeeklyCheck[];
}

export const defaultSettings: Settings = {
  masterVolume: 0.5,
  preferredEar: 'both',
  notchWidthOctaves: 1,
  dailyGoalMin: 60,
  name: '',
};

export function emptyData(): AppData {
  return {
    version: 1,
    settings: { ...defaultSettings },
    hearingTests: [],
    matches: [],
    riTrials: [],
    sessions: [],
    journal: [],
    weekly: [],
  };
}
