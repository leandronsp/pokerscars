// Sound preferences in localStorage, read defensively: a corrupt value is
// never trusted, a missing store never throws. Sounds ship OFF by default;
// browsers demand a gesture before audio anyway, so opting in is honest.

export interface SoundPrefs {
  enabled: boolean;
  turn: boolean;
  win: boolean;
  end: boolean;
}

const KEY = 'pokerscars-sounds';
const DEFAULTS: SoundPrefs = { enabled: false, turn: true, win: true, end: true };

export function loadPrefs(): SoundPrefs {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw === null) return { ...DEFAULTS };
    const parsed = JSON.parse(raw) as Partial<SoundPrefs>;
    return {
      enabled: parsed.enabled === true,
      turn: parsed.turn !== false,
      win: parsed.win !== false,
      end: parsed.end !== false,
    };
  } catch {
    return { ...DEFAULTS };
  }
}

export function savePrefs(prefs: SoundPrefs): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(prefs));
  } catch {
    // best effort: private mode or full storage never breaks the game
  }
}
