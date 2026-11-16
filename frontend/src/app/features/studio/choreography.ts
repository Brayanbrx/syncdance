/**
 * Counting on the master video: taps to tempo, video time to beats.
 * The server keeps steps in beats from the first "1" (`apps/studio/choreography.py`).
 */

export const MIN_BPM = 60;
export const MAX_BPM = 180;
export const MIN_TAPS = 8;
export const MAX_COUNTS = 32;
/** A pause longer than this between taps starts a new series. */
export const TAP_GAP_MS = 2500;

export interface Tempo {
  bpm: number;
  firstBeatMs: number;
}

export function beatMs(bpm: number): number {
  return 60000 / bpm;
}

/**
 * Tempo and first beat from taps on the beat, in video time (ms), the first
 * tap on the first "1". A straight line through the taps: steady over a long
 * series, and a missed beat only skips an index instead of halving the tempo.
 */
export function fitTaps(times: number[]): Tempo | null {
  if (times.length < MIN_TAPS) return null;
  const gaps = times
    .slice(1)
    .map((t, i) => t - times[i])
    .sort((a, b) => a - b);
  const typical = gaps[Math.floor(gaps.length / 2)];
  if (!(typical > 0)) return null;
  const index = times.map((t) => Math.round((t - times[0]) / typical));
  const n = times.length;
  const meanI = index.reduce((a, b) => a + b, 0) / n;
  const meanT = times.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let k = 0; k < n; k++) {
    num += (index[k] - meanI) * (times[k] - meanT);
    den += (index[k] - meanI) ** 2;
  }
  if (den === 0) return null;
  const beat = num / den;
  const bpm = Math.round((60000 / beat) * 100) / 100;
  if (!(bpm >= MIN_BPM && bpm <= MAX_BPM)) return null;
  return { bpm, firstBeatMs: Math.max(0, Math.round(meanT - beat * meanI)) };
}

/** The beat being danced at `positionMs` (0 = the first "1"); null before it. */
export function beatAt(positionMs: number, tempo: Tempo): number | null {
  const beat = Math.floor((positionMs - tempo.firstBeatMs) / beatMs(tempo.bpm) + 1e-6);
  return beat < 0 ? null : beat;
}

/** The nearest beat to `positionMs`, never before the first "1". */
export function nearestBeat(positionMs: number, tempo: Tempo): number {
  return Math.max(0, Math.round((positionMs - tempo.firstBeatMs) / beatMs(tempo.bpm)));
}

export function beatToMs(beat: number, tempo: Tempo): number {
  return Math.round(tempo.firstBeatMs + beat * beatMs(tempo.bpm));
}

/** Dancers count in eights: beat 13 is the 6 of the second eight. */
export function countOf(beat: number): { eight: number; count: number } {
  return { eight: Math.floor(beat / 8) + 1, count: (beat % 8) + 1 };
}

export interface StepRange {
  start_beat: number;
  counts: number;
}

/** Indexes of steps that start before the previous one ends (in beat order). */
export function overlapping(steps: StepRange[]): Set<number> {
  const order = steps
    .map((step, i) => ({ step, i }))
    .sort((a, b) => a.step.start_beat - b.step.start_beat);
  const bad = new Set<number>();
  for (let k = 1; k < order.length; k++) {
    const previous = order[k - 1].step;
    if (order[k].step.start_beat < previous.start_beat + previous.counts) bad.add(order[k].i);
  }
  return bad;
}
