// The LiveView seam for sounds. The server decides WHEN a cue happens
// (push_event "sound"); this hook decides WHETHER to play it (prefs) and
// owns the preference checkboxes rendered inside its phx-update="ignore"
// element. Only the primary instance listens for events, so the drawer
// copy of the settings never double-plays.

import { SoundEngine, SoundKind } from './engine.ts';
import { loadPrefs, savePrefs, SoundPrefs } from './prefs.ts';

const engine = new SoundEngine();

interface SoundsHook {
  el: HTMLElement;
  handleEvent(event: string, callback: (payload: { kind: SoundKind }) => void): void;
}

export const Sounds = {
  mounted(this: SoundsHook): void {
    document.addEventListener('pointerdown', () => engine.unlock());

    if (this.el.dataset.primary !== undefined) {
      this.handleEvent('sound', ({ kind }) => {
        const prefs = loadPrefs();
        if (prefs.enabled && prefs[kind]) engine.play(kind);
      });
    }

    const inputs = this.el.querySelectorAll<HTMLInputElement>('input[data-sound-pref]');
    const render = (prefs: SoundPrefs) => {
      inputs.forEach((input) => {
        const key = input.dataset.soundPref as keyof SoundPrefs;
        input.checked = prefs[key];
        // The master gates the cue toggles: greyed out until sounds are on.
        input.disabled = key !== 'enabled' && !prefs.enabled;
      });
    };
    render(loadPrefs());

    inputs.forEach((input) => {
      input.addEventListener('change', () => {
        const prefs = loadPrefs();
        prefs[input.dataset.soundPref as keyof SoundPrefs] = input.checked;
        savePrefs(prefs);
        render(prefs);
        if (input.checked) engine.unlock();
      });
    });
  },
};
