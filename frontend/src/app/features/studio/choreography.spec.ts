import { beatAt, beatToMs, countOf, fitTaps, nearestBeat, overlapping } from './choreography';

describe('choreography counting', () => {
  const tempo = { bpm: 120, firstBeatMs: 1000 }; // a beat every 500 ms

  it('finds tempo and first beat from steady taps', () => {
    const taps = Array.from({ length: 12 }, (_, i) => 1000 + i * 500);
    expect(fitTaps(taps)).toEqual({ bpm: 120, firstBeatMs: 1000 });
  });

  it('averages out human jitter and survives a missed beat', () => {
    const jitter = [12, -9, 4, -15, 8, 0, -6, 11, -3, 7];
    const taps = jitter.map((j, i) => 2000 + i * 535.714 + j).filter((_, i) => i !== 5);
    const fit = fitTaps(taps)!;
    expect(fit.bpm).toBeCloseTo(112, 0);
    expect(Math.abs(fit.firstBeatMs - 2000)).toBeLessThan(15);
  });

  it('waits for enough taps and a danceable tempo', () => {
    expect(fitTaps([0, 500, 1000])).toBeNull();
    const tooSlow = Array.from({ length: 8 }, (_, i) => i * 2000);
    expect(fitTaps(tooSlow)).toBeNull();
  });

  it('counts in eights from the first beat', () => {
    expect(beatAt(999, tempo)).toBeNull();
    expect(beatAt(1000, tempo)).toBe(0);
    expect(beatAt(7499, tempo)).toBe(12);
    expect(countOf(12)).toEqual({ eight: 2, count: 5 });
    expect(nearestBeat(1260, tempo)).toBe(1);
    expect(nearestBeat(200, tempo)).toBe(0);
    expect(beatToMs(16, tempo)).toBe(9000);
  });

  it('flags steps that start before the previous one ends', () => {
    const steps = [
      { start_beat: 8, counts: 4 },
      { start_beat: 0, counts: 8 },
      { start_beat: 10, counts: 8 },
    ];
    expect([...overlapping(steps)]).toEqual([2]);
  });
});
