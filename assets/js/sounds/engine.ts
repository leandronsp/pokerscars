// The whole sound engine: three synthesized cues, no samples, no buffers.
// Notes are oscillators through a per-note gain envelope into a master bus,
// the voxquad shape. Everything is lazy: the AudioContext only exists after
// the first user gesture unlocks it.

export type SoundKind = 'turn' | 'win' | 'end' | 'raise' | 'all_in';

interface EnvelopePoint {
  gain: number;
  time: number;
}

// Pure: attack/decay/release points for a short UI cue.
export function cueEnvelope(startAt: number, duration: number, peak: number): EnvelopePoint[] {
  const attack = Math.min(0.02, duration * 0.3);
  const release = Math.max(attack, duration * 0.6);
  return [
    { gain: 0, time: startAt },
    { gain: peak, time: startAt + attack },
    { gain: peak * 0.6, time: startAt + release },
    { gain: 0, time: startAt + duration },
  ];
}

export class SoundEngine {
  private context: AudioContext | null = null;
  private master: GainNode | null = null;

  // iOS suspends the context on backgrounding; resume on every gesture.
  unlock(): void {
    void this.ensure().resume().catch(() => {});
  }

  play(kind: SoundKind): void {
    const now = this.ensure().currentTime + 0.02;
    if (kind === 'turn') {
      this.note(660, now, 0.12);
      this.note(880, now + 0.11, 0.16);
    } else if (kind === 'win') {
      [523, 659, 784, 1047].forEach((freq, step) => this.note(freq, now + step * 0.09, 0.18));
    } else if (kind === 'raise') {
      // the "uhul": a quick upward whoop and a bright ping on top
      this.note(440, now, 0.16, 'sawtooth', 880);
      this.note(1320, now + 0.14, 0.1);
    } else if (kind === 'all_in') {
      // aura: a low riser under a slow golden shimmer
      this.note(98, now, 0.7, 'triangle', 196);
      [880, 1109, 1319].forEach((freq, step) => this.note(freq, now + 0.18 + step * 0.16, 0.28));
    } else {
      this.note(330, now, 0.22, 'triangle', 165);
    }
  }

  private note(
    freq: number,
    at: number,
    duration: number,
    type: OscillatorType = 'sine',
    glideTo: number | null = null,
  ): void {
    const context = this.ensure();
    const oscillator = context.createOscillator();
    const envelope = context.createGain();

    oscillator.type = type;
    oscillator.frequency.setValueAtTime(freq, at);
    if (glideTo !== null) oscillator.frequency.exponentialRampToValueAtTime(glideTo, at + duration);

    const points = cueEnvelope(at, duration, 0.3);
    envelope.gain.setValueAtTime(points[0].gain, points[0].time);
    for (const point of points.slice(1)) envelope.gain.linearRampToValueAtTime(point.gain, point.time);

    oscillator.connect(envelope);
    envelope.connect(this.master!);
    oscillator.start(at);
    oscillator.stop(at + duration + 0.05);
  }

  private ensure(): AudioContext {
    if (this.context === null) {
      this.context = new AudioContext();
      this.master = this.context.createGain();
      this.master.gain.value = 0.5;
      this.master.connect(this.context.destination);
    }
    return this.context;
  }
}
