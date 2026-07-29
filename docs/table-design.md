# Table design — layout, components, tokens

R&D output for ROADMAP Step 1, feeding Step 6 (Table LiveView). Decision-oriented:
what we build, and what we rejected. All user-facing strings go through Gettext
(`pt_BR` source) — this doc fixes structure, never copy.

## 1. Layout system

### Geometry: one angle per seat, projected onto a themed ellipse

Commercial clients (PokerStars, GGPoker, ClubGG) ship hand-authored coordinates
per seat count, because evenly-spaced angles on an ellipse crowd at the horizontal
extremes. We keep the hand-tuning but reduce it to **one number per seat**: an
angle, from which position is derived, so responsiveness is free.

θ is degrees, `0° = bottom-center = hero`, increasing toward **screen-left** (the
player to your left sits to your left in a bird's-eye view). Gaps shrink toward
180° to compensate for the ellipse.

```elixir
@seat_angles %{
  2 => [0, 180],
  3 => [0, 120, 240],
  4 => [0, 90, 180, 270],
  5 => [0, 75, 145, 215, 285],
  6 => [0, 65, 125, 180, 235, 295],
  7 => [0, 58, 110, 158, 202, 250, 302],
  8 => [0, 52, 100, 143, 180, 217, 260, 308],
  9 => [0, 48, 92, 132, 166, 194, 228, 268, 312]
}
```

Each seat renders two unit-free custom properties, computed at compile time from
the table above (`--sx = -sin θ`, `--sy = cos θ`):

```css
.pk-seat {
  position: absolute;
  left: calc(50% + var(--sx) * var(--pk-felt-rx));
  top:  calc(50% + var(--sy) * var(--pk-felt-ry));
  transform: translate(-50%, -50%);
}
```

`--pk-felt-rx` is a percentage of felt width, `--pk-felt-ry` of felt height, so a
breakpoint changes two numbers and the felt's `aspect-ratio`, nothing else.

| | felt `aspect-ratio` | `--pk-felt-rx` | `--pk-felt-ry` |
|---|---|---|---|
| phone portrait (`< 40rem`) | `3 / 4` (tall oval) | `40%` | `42%` |
| desktop / landscape | `16 / 10` (wide oval) | `42%` | `40%` |

Felt is `max-width: min(94vw, 1100px)`, centered, with the action bar outside it
in normal flow so it can never overlap a seat.

> Verify at friends-night whether pokernow orders seats toward screen-left or
> screen-right from the hero. Ours is the bird's-eye-correct direction; if it feels
> mirrored, flipping the sign of `--sx` is the entire fix.

**Hero rotation happens on the server**, in the projection that already filters
per-seat secrets, so one place decides what a socket sees:
`display_slot = Integer.mod(seat.index - hero_index, seat_count)`. Spectators get
`hero_index = button_index`.

**Empty seats are rendered, never hidden** — hiding collapses the ellipse and makes
the table jump at the worst moment. An empty seat is a dashed-hairline pod with a
`phx-click="sit"` target and the footprint of an occupied one.

### Sketch — 6-max

```
DESKTOP (16/10 felt)                            PHONE PORTRAIT (3/4 felt)
┌──────────────────────────────────────────┐    ┌──────────────────────┐
│ Mesa do Léo    BB 1    6/6          [≡]  │    │ Mesa do Léo  6/6   ≡ │
│                                          │    │                      │
│            ┌────────┐                    │    │     ┌────────┐       │
│            │Rui  310│                    │    │     │Rui  310│       │
│            └────180°┘                    │    │     └───180°─┘       │
│  ┌────────┐            ┌────────┐        │    │┌────────┐┌────────┐  │
│  │Bia  480│    ▪20     │Tom  155│        │    ││Bia  480││Tom  155│  │
│  └───125°─┘            └───235°─┘        │    │└──125°──┘└──235°──┘  │
│                                          │    │                      │
│             POT  84                      │    │      POT  84         │
│     ┌──┐┌──┐┌──┐┌──┐┌──┐                 │    │  ┌─┐┌─┐┌─┐┌─┐┌─┐     │
│     │A♠││K♦││7♣││░░││░░│                 │    │  │A♠││K♦││7♣││░││░│  │
│     └──┘└──┘└──┘└──┘└──┘                 │    │  └─┘└─┘└─┘└─┘└─┘     │
│                                          │    │                      │
│  ┌────────┐            ┌────────┐        │    │┌────────┐┌────────┐  │
│  │Ana  920│ ▪40   ▪40  │Zé   700│  (D)   │    ││Ana  920││Zé   700│  │
│  └────65°─┘            └───295°─┘        │    │└──65°───┘└──295°──┘  │
│                                          │    │                      │
│           ┌────────────┐                 │    │   ┌────────────┐(D)  │
│           │ ┌──┐┌──┐   │                 │    │   │ ┌──┐┌──┐   │     │
│           │ │Q♥││Q♠│   │                 │    │   │ │Q♥││Q♠│   │     │
│           │ Léo   1240 │                 │    │   │ Léo   1240 │     │
│           └─────0°─────┘                 │    │   └─────0°─────┘     │
│                                          │    │                      │
│ ┌────────┬───────────┬──────────────┐    │    │┌────┬───────┬─────┐  │
│ │  FOLD  │  CALL 40  │   RAISE ▸    │    │    ││FOLD│CALL 40│RAISE│  │
│ └────────┴───────────┴──────────────┘    │    │└────┴───────┴─────┘  │
└──────────────────────────────────────────┘    └──────────────────────┘
```

**Seat pod**: nickname · stack · avatar disc carrying the timer ring · status
badge (`sitting out`, `all-in`; `folded` dims the pod to 45%). Bet chips sit
between the pod and the pot, on the seat→center line, using the same trick at a
smaller radius (`--pk-bet-rx`). The dealer button uses a third radius.

## 2. Cards

**Decision: hand-drawn inline SVG function component.** No asset files, no
dependency, no sprite sheet. At our sizes a card is a rounded rect, a rank string
and a suit glyph — under 20 lines of HEEx — and it buys theme tokens on the face
(`fill="var(--pk-card-face)"`), a real `<title>` for screen readers, and diffable
server rendering. Rejected: Unicode card glyphs (`🂡`), which
`begleynk/phoenix-poker` shipped and has an open TODO to move off over
browser/font coverage; and SVG-cards (Bellot) / Vector Playing Cards (Aguilar),
both LGPL with attribution duty and court art invisible below ~80px anyway.

**Four-colour deck is the default, not an option.** Spades black, hearts red,
diamonds blue, clubs green — the Caro convention, standard online since the early
WPT broadcasts. It buys suit recognition at a glance on a phone and helps
colour-blind players. Colour never carries the suit alone; the glyph is always drawn.

| role | phone | desktop | rendering |
|---|---|---|---|
| hero hole cards | 56 × 78 | 64 × 90 | corner index + large center suit |
| board | 44 × 62 | 56 × 78 | corner index + large center suit |
| opponent (shown/back) | 28 × 40 | 34 × 48 | corner index only |

The switch is at 40px width: below it, corner index only. That keeps the 44px
phone board card fully drawn and strips only opponent cards. (The documented
threshold is ~75px in `responsive-playing-cards`, but that is for full-art faces;
ours are already minimal.) Card backs are CSS, not art: `--pk-card-back` plus a
`repeating-linear-gradient` weave, themeable for free.

## 3. Action bar

Fixed three-slot grid. Slots keep their geometry in every state so muscle memory
holds:

```
[ FOLD ] [ CHECK | CALL <n> ] [ BET | RAISE ▸ ]
```

**Fold is not rendered when checking is free** (PokerStars removed it for exactly
this misclick). The slot stays empty rather than letting Check slide into Fold's
position; a disabled button is still a tap target.

**Sizing is a second step, and that is the misclick guard.** Tapping `RAISE ▸`
replaces the bar in place — no modal, no overlay, same footprint:

```
[ 1/2 ] [ 2/3 ] [ POT ] [ ALL-IN ]      ← presets, chip-shaped
[ ──────●───────────────────── ]        ← slider, snapped to legal increments
[ ← BACK ]            [ RAISE TO 160 ]  ← the only committing button
```

⅔ pot is the conventional default; ½–¾ is the working range. The slider clamps to
`[min_raise, hero_stack]`, snaps to big-blind multiples, and flags invalid drag
positions visually rather than rejecting after release. All-in takes one extra
confirm tap; nothing else does — a modal on every action kills pace of play.

**Pre-actions.** While it is not your turn, a compact checkbox row sits above the
bar: `Check/Fold` (one combined intent, per PokerStars' hotkey semantics — checks
if legal, else folds), `Call any`, `Check`. All clear whenever the board or the
amount-to-call changes, and the server revalidates against real state before
applying.

**Turn indication.**

- *Timer ring*: an SVG circle around the acting avatar, `stroke-dashoffset` plus
  `animation: countdown var(--pk-turn-ms) linear forwards`. Reconnect resumes via
  `animation-delay: calc(-1ms * var(--pk-elapsed))` from the server's deadline.
  Pure CSS: zero per-second messages. Accent → danger in the last 25%.
- *Sound*: a cue on your turn only, volume adjustable independently of everything
  else (a long-standing PokerStars complaint).
- *Vibration*: `navigator.vibrate()` needs a visible document, so it fires on
  turn-start when foregrounded, and on `visibilitychange` if the turn is still live
  when you return.
- *Backgrounded tab*: alternate `document.title` while hidden, stop on
  `visibilitychange`. Notifications API only on opt-in.

## 4. Table flow legibility

- **Pot** in the felt center above the board, one number, no count-up. Side pots
  stack as smaller labelled rows beneath.
- **Bet chips** stay in front of each seat until the street closes, then travel to
  the pot in one animation. Denomination-coloured discs (max 5 stacked, `+n` beyond)
  with the amount beside them — the number is the truth, the discs are the
  glanceable layer.
- **Street transitions**: board cards deal in staggered, and the pot region
  announces the new street via `aria-live="polite"`.
- **Showdown order follows the rule, not the UI's convenience**: the river's last
  aggressor shows first; if the river checked through, reveal runs in action order
  from the left of the button. Beaten hands auto-muck unless obliged to show, with
  a per-player `Show` button for the social case.
- **Winner**: winning hole + board cards get a `--pk-win` outline glow, the pot
  slides to the seat, the hand's name renders under the board for ~2s.
- **Hand history**: a slide-over panel of recent hands (hand #, board, winner, pot),
  each expandable to its action log, built from events the table process already
  emits. pokernow's own history is thin enough that a third-party converter
  ecosystem grew around it, so this is a cheap differentiator; the Step 7 ledger
  shares the panel.

## 5. Components and hooks

`lib/pokerscars_web/components/` — function components only, no LiveComponents.

| module / function | responsibility |
|---|---|
| `card.ex` `<.card>` | one card face as inline SVG, size variant, a11y title |
| `card.ex` `<.card_back>` | face-down card, CSS-drawn back |
| `card.ex` `<.card_fan>` | a row of cards carrying stagger indices for dealing |
| `table_components.ex` `<.felt>` | the positioned ellipse container and its tokens |
| `table_components.ex` `<.seat>` | one seat pod at its angle: name, stack, badges |
| `table_components.ex` `<.empty_seat>` | dashed placeholder with the sit target |
| `table_components.ex` `<.timer_ring>` | the SVG countdown arc around an avatar |
| `table_components.ex` `<.bet_chips>` | chips in front of a seat, on the seat→pot line |
| `table_components.ex` `<.dealer_button>` | the button disc, positioned like a seat |
| `table_components.ex` `<.pot>` | main pot plus side pots |
| `table_components.ex` `<.board>` | community cards with per-street reveal |
| `action_components.ex` `<.action_bar>` | the three fixed slots and their legal states |
| `action_components.ex` `<.sizing_panel>` | presets, slider, commit button |
| `action_components.ex` `<.pre_actions>` | out-of-turn checkbox row |
| `history_components.ex` `<.hand_log>` | slide-over hand history / ledger panel |

`assets/js/` — **two hooks, both narrow**: `BetSlider` (owns the range input
while dragging, pushes only on release) and `TurnAlert` (sound, vibration, title
flash; reacts to `push_event` only, owns no DOM).

### The voxquad question: does the table need a client-autonomous island?

**Not the table.** Voxquad pins its player under `phx-hook` + `phx-update="ignore"`
because the client owns the truth — audio and cursor must survive a socket drop.
Here the server owns everything and a reconnect *should* repaint from authoritative
state: showing a stale table through a drop is worse than a flicker.

**Yes for the bet slider, and only there.** A range input dragged at 60fps over
ngrok is the one genuinely bad case for round-trips, and LiveView would clobber the
value mid-drag. `phx-update="ignore"` on the wrapper, label updated client-side,
one `phx-change` on release. Voxquad's lesson at its actual scope.

### What the other repos give us, and what they do not

- **mendio** — take `Phoenix.Presence` for "who is actually connected" (grey out a
  disconnected pod instead of silently auto-folding) and its `on_mount` shape for
  resolving a seat from the room token. Its Figma-sourced UI, Oban, Stripe,
  LGPD/health-data rules and WebRTC do not apply.
- **pitchr** — take the `core_components` / `<domain>_components` file split. Its
  SaaS auth, Cloudflare landing and waitlist tooling do not apply.
- **voxquad** — take the token layer and `[data-theme]` strategy below, wholesale.
  Its Web Audio pipeline, OSMD rendering and IndexedDB device-local storage do not
  apply; we have no client-side domain state.

## 6. Design tokens and theming

Tailwind v4 `@theme` for anything that should generate utilities, plain custom
properties under `[data-theme=...]` for the rest — voxquad's pattern. Everything
is `--pk-` prefixed so it never collides with generator output.

**daisyUI stays out of the table.** `phx.new` left the plugin and two daisy themes
in `app.css`, and `core_components.ex` uses `input`/`btn`/`alert` classes.
AGENTS.md forbids daisy components, and a felt, a rail and four suit colours do
not fit the `base-100`/`primary` vocabulary. The table defines its own layer and
touches nothing daisy; stripping daisy from the lobby forms is a separate cleanup.

Structural tokens are theme-independent and live once on `:root`:

```css
:root {
  --pk-felt-rx: 42%;  --pk-felt-ry: 40%;   /* geometry — breakpoints override */
  --pk-bet-rx: 26%;   --pk-bet-ry: 25%;    /* chips, on the seat→pot line */
  --pk-btn-rx: 32%;   --pk-btn-ry: 31%;    /* dealer button */

  --pk-radius-card: 6px;    --pk-radius-pod: 12px;
  --pk-radius-action: 10px; --pk-radius-pill: 999px;

  --pk-t-fast: 120ms;  --pk-t: 180ms;  --pk-t-slow: 300ms;  --pk-deal-stagger: 40ms;

  --pk-z-felt: 0;    --pk-z-bets: 10;    --pk-z-seats: 20;
  --pk-z-cards: 30;  --pk-z-action: 40;  --pk-z-panel: 50;
}
```

Every theme must define all of the following. Default theme is **`feltro`**:

```css
[data-theme='feltro'] {
  --pk-page: #0d1512;            /* behind the felt */
  --pk-felt: #14563c;            --pk-felt-glow: #1c6f4c;  /* base, radial center */
  --pk-rail: #3a2418;            --pk-rail-edge: #57392a;  /* dark walnut edge */

  --pk-surface: #16211c;         --pk-surface-raised: #1e2d26;  /* pod, active pod */
  --pk-hairline: rgba(232, 240, 234, 0.12);
  --pk-text: #e8f0ea;            --pk-text-muted: #93a89c;

  --pk-accent: #e5a83c;          --pk-on-accent: #1a1208;  /* hero, ring, raise */
  --pk-fold: #b4463c;            --pk-call: #2f8f5b;
  --pk-raise: #e5a83c;           --pk-danger: #b4463c;     --pk-win: #f2d16b;

  --pk-card-face: #f7f4ec;       --pk-card-ink: #1a1a1a;   --pk-card-back: #7a2c2c;

  /* four-colour deck */
  --pk-suit-spade: #1a1a1a;      --pk-suit-heart: #c1352c;
  --pk-suit-diamond: #2464b4;    --pk-suit-club: #1e7a45;

  /* chip denominations */
  --pk-chip-1: #f2efe6;    --pk-chip-5: #c1443a;     --pk-chip-25: #2f8f5b;
  --pk-chip-100: #22262a;  --pk-chip-500: #6b4fa8;   --pk-chip-1000: #e5c145;
}
```

A second theme (`carvao`, dark minimal: charcoal felt, no wood rail, cooler
accent) redefines that same list and nothing else. Theme is a `data-theme`
attribute on `<html>`, set before paint by the inline script already in
`root.html.heex`.

## 7. Animation budget

`transform` and `opacity` only. Nothing over 300ms. Nothing that triggers layout.

| animates | how | duration |
|---|---|---|
| card deal | `translate` from deck origin + `opacity` | 120ms, 40ms stagger |
| card flip | `rotateY` on a two-face wrapper | 180ms |
| bet chips → pot | `translate` along the seat→center line | 220ms |
| pot → winner | `translate` + fade | 300ms |
| timer ring | `stroke-dashoffset`, CSS-driven from deadline | turn length |
| acting pod | `opacity` pulse on a glow layer | 1.2s loop |
| winner cards | `outline-color` + `opacity` on a glow layer | 300ms, holds 2s |

**Never animates**: seat positions (the felt must read as static), pot and stack
numbers (they snap — a tweening number on a phone reads as network lag, the one
impression a poker table must never give), `top`/`left`/`width`/`height`,
`backdrop-filter` on the felt, shadows on more than the focused element.

`prefers-reduced-motion: reduce` disables deal, flip, chip travel, pot travel and
the pulse. The timer ring survives; it is information, not decoration.

## 8. Accessibility

- **Timing (WCAG 2.2.1, Level A)** is the real constraint — an auto-folding action
  clock is a time limit. Satisfied by a host-configurable clock length, a visible
  countdown, a warning at 25% remaining (ring turns `--pk-danger`, plus sound and
  vibration), and a per-player time bank that extends it.
- **Suit is never colour alone.** The glyph is always drawn; four colours are an
  accelerator, not the encoding.
- **Every card carries an SVG `<title>`** ("Ace of spades", via Gettext); the
  hole-card group carries an `aria-label` summarising the hand.
- **`aria-live="polite"`** for street changes, pot changes and showdown results;
  **`assertive`**, once, for "your turn".
- **44px minimum touch targets** on every action button and preset chip; the bar
  respects `env(safe-area-inset-bottom)`.
- **Keyboard**: `F` fold, `C` check/call, `R` open sizing, `Enter` commit, `Esc`
  back out. Focus opens on the safest legal action — check if free, else call,
  never raise.
- Contrast: `--pk-text` on `--pk-surface`, and every action label on its button
  colour, must clear 4.5:1. The default theme is chosen to satisfy this.

## 9. Decisions

| Decision | Rejected | Why |
|---|---|---|
| One angle per seat → ellipse via custom props | Hand-authored `top`/`left` per seat per breakpoint | 2 breakpoints × 8 counts = 16 tables to maintain; angles give the same control in one number per seat, responsive for free. |
| Tall oval on phone, wide oval on desktop | Force landscape on mobile | ClubGG is portrait-only and PokerStars shipped portrait tables in 2023; landscape is multi-tabling legacy. Friends on phones will not rotate. |
| Hero rotation in the LiveView projection | CSS transform on the felt; client-side rotation | The projection already filters per-seat secrets. One place decides what a socket sees. |
| Empty seats rendered as sit targets | Hide them, collapse the ellipse | Hiding makes the table jump when someone sits or leaves — the worst moment for a stable read. |
| Hand-drawn inline SVG cards | Unicode glyphs; LGPL decks; sprite sheet; canvas | Unicode is proven broken (`begleynk/phoenix-poker`'s own TODO). LGPL decks add attribution and unreadable court art. Sprites and canvas lose theming and screen-reader text. |
| Four-colour deck by default | Two-colour with a toggle | Legibility on a 44px board card is the whole game on a phone; the default should be the readable one. |
| Plain LiveView re-render for the table | voxquad's `phx-update="ignore"` island | Server owns all state, so repainting on reconnect is correct. Voxquad ignores because its client owns the audio timeline. |
| `phx-update="ignore"` island for the bet slider only | `phx-change` per drag frame; steppers instead | 60fps round-trips over ngrok is the one bad case. Steppers are slower than a slider across a 20→900 range. |
| Two-step raise (bar becomes sizing panel) | Modal dialog; confirm on every action | Same footprint means no layout shift and nothing to dismiss. Confirming everything destroys pace; confirming all-in is enough. |
| Fold hidden when check is free | Fold visible but disabled | PokerStars removed it for exactly this misclick; a disabled button is still a tap target. |
| CSS timer ring from a server deadline | JS interval; per-second server ticks | Zero messages per second per player, and reconnect resumes via negative `animation-delay`. |
| `--pk-*` token layer, daisyUI untouched | Extend daisy themes with felt colours | A felt, a rail and four suit colours do not fit `base-100`/`primary`; AGENTS.md forbids daisy components regardless. |
| Pot and stack numbers snap | Count-up tween | On a phone a tweening number reads as lag. |
