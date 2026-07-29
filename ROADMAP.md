# Roadmap

Living document: update step status as work lands, fold findings back in.
Founding intent lives in `PROMPT.md`. Statuses: `done`, `in progress`, `next`,
`later`.

## Step 0 — Skeleton — done

Phoenix 1.8.9 / Elixir 1.20.2 / LiveView 1.2.8, all in Docker (web on 4300,
Postgres on 5444, clear of the other local stacks). `mix check` gate: format,
unused deps, compile --warnings-as-errors, Credo, Dialyzer with
`:unmatched_returns`, tests. Make targets grouped per context. Gettext with
pt_BR as source locale. CLAUDE.md + `.claude/rules/` for typing and
architecture.

## Step 1 — R&D: poker engine + table design — done

Two research lines, docs are the source of truth for Steps 2-6:

- `docs/engine-design.md` — pure engine, seed injected (hands replayable),
  naive 21-combination evaluator (no lookup tables), four-action union with
  all-in implicit, pots derived from `Seat.contributed` (never accumulated),
  `legal_actions/1` computes raise min/max for the UI, 30 named mandatory
  tests. Simplified button rules (join waits for BB, heads-up button = SB).
- `docs/table-design.md` — one angle per seat projected on a themed ellipse
  (custom props, 2 breakpoints), hand-drawn inline SVG cards, four-colour
  deck by default, three-slot action bar with in-place sizing panel (all-in
  is the only confirm), CSS timer ring from a server deadline (zero ticks),
  `--pk-*` token layer with `feltro` as default theme, plain LiveView
  re-render everywhere except a `phx-update="ignore"` bet slider.

## Step 2 — Engine: cards and hand evaluation — done

`Card` (fixture notation parsing), `Deck` (seeded Fisher-Yates, deal),
`HandRank` (category + tiebreak, total order), `Evaluator` (21-combination
max). Evaluation tests 1-9 from the engine doc plus 4 properties
(permutation, monotonicity, suit relabeling, shuffle permutation).
Note: the doc's test 2 ("straight flush and quads in the same 7 cards") is
unconstructible — 5+4 with max overlap 1 needs 8 cards — so it landed as a
cross-hand comparison instead. Engine facade deferred until the table
context exists to call it.

## Step 3 — Engine: betting round state machine — done

`Seat`, `BettingRound` (min-raise + incomplete-all-in reopening via the two
per-seat booleans), `Pot.build` with refunds and layer merging, `Showdown`
with odd-chip TDA rule, `Button` (heads-up exception), `Hand` lifecycle with
runout and uncontested exits. The acceptance-criteria tests (14, 15, 25, 26)
pass. The chip-conservation property found one real bug during development:
the last contender must never get a turn (an open fold would leave the pot
ownerless) — `maybe_advance` checks contenders before round closure.

## Step 4 — Table process — done

GenServer per table via Registry + DynamicSupervisor. Auto-starts hands with
2+ funded seats, 30s turn clock auto-checks/folds absentees, per-player
projection (`Table.View`) is the only thing sockets ever see, ledger entries
on sit/rebuy/stand. Rebuys and stands mid-hand queue until the hand ends.

## Steps 5+6 — Lobby and table screen — done

Lobby creates a table (blinds presets) and joins by code. Identity is an
anonymous session cookie (`EnsurePlayerId`). The table screen implements the
design doc: angle-projected felt, hero rotation server-side, SVG four-colour
cards, three-slot action bar with in-place sizing panel (all-in double-tap
confirm), CSS timer ring from the server deadline, `feltro` tokens. UI
strings are pt-BR msgids through Gettext (source locale; en comes later as
a .po). Browser-tested multiplayer: two sessions played hands to showdown.

## Step 7 — Ledger — done (in-memory)

Buy-in/rebuy/cash-out in cents, settlement drawer (nets to zero), Pix note.
The ledger lives in the table process: a BEAM restart wipes tables AND the
money record. Fine for an MVP night; persisting entries to Postgres is the
first hardening task if real stakes grow.

## Round 2 — solo mode, exhaustive coverage, open tables — done

- **Bots** (`lib/pokerscars/bots/`): "chamar bot" seats a rule-based bot
  (100BB buy-in, auto-rebuy) that plays through the same `Table` door as a
  human — no access to hidden state. Two bots play whole hands unattended.
- **Exhaustive tests**: all 2,598,960 five-card hands checked against the
  known frequency table (7-card follows from max-over-21-subsets +
  monotonicity property); every legal action sequence of whole hands walked
  for heads-up and 3-way short-stack configs, chips conserved at every leaf.
- **Lobby lists open tables** (name, blinds, seat count) with live updates.
- Fix: the colocated slider hook broke LiveView patching in the real
  browser (tests can't catch it — no JS); replaced by a `phx-throttle`d
  form input. Less machinery, one fewer island.

## Round 3 — the UX pass — done

Feedback-driven overhaul after real play: classic two-colour deck (the
four-colour experiment lost to reality), cards ~40% bigger with safe glyph
margins, dealer disc and turn ring moved onto the pod (they covered cards),
"tua mão · dois pares" chip always visible, current-bet pill + "raise" tag
on the aggressor's chips, winner celebration (gold pod, lifted cards,
gradient banner with the winning hand name), deal-in animations, compact
action bar (fold as outline), cashier as a printed bar-tab receipt, turn
clock configurable per table (30/45/60/90s, default 45), tables closable
from the lobby (viewers redirected, bots stop). Felt/rail rebuilt with
layered gradients and an inlay ring.

## Round 4 — stability, i18n and table language — done

- **The table never moves**: the action zone has a fixed height, so
  action bar / sizing / status swaps stop nudging the felt (measured:
  identical bounding box before and after).
- **Bets ride each seat** (pill above the player), killing every overlap
  with board cards; the aggressor's pill is tagged "aumentou".
- **Pot block** got hierarchy: chip-stack art + serif gold amount, with
  "aposta atual" beside it. Chips brighter and bigger.
- **Raise presets on the bar** (1/2 · 2/3 · pote · all-in with amounts),
  one tap commits; the slider became the optional "outro valor" path.
- **Stable card ids** stop patch-replays of the deal animation (the river
  flicker); animations retimed to glide (420ms, staggered).
- **Full i18n**: pt-BR source without anglicisms (desistir/passar/pagar/
  apostar/aumentar, desistiu), complete `en` catalog, locale + currency
  (R$/$/€) switchers in the top bar backed by session prefs.
- **Showdown**: every revealed seat wears its hand name over the pod;
  losers get "esconder cartas" (muck) during the pause.
- **Rebuys queue mid-hand** and land when the hand ends (the old
  between-hands-only window was nearly unhittable on bot tables); first
  hand starts in 1s. Buy-in inputs are prefilled and required.
- Table has a "← lobby" button; casino styling pass (serif display type,
  conic-ray backdrop, brass panel borders).

## Round 5 — mobile-first, side cards, explicit settlements — done

- **Mobile-first**: felt-first stacking on phones, tighter geometry (no seat
  clipping at 390px), no horizontal scroll, 44px tap targets, cashier as a
  drawer. Verified by a 42-check `agent-browser` smoke battery (desktop +
  390x844) that now gates "done" — `scratchpad/smoke.sh` pattern.
- **Explicit settlements**: every pot announced by name — "X leva o pote
  principal (4,50) · Y leva o pote lateral (1,00)", splits as "dividem";
  between-hands pause 4s → 7s so people can read it.
- **Layout**: config card on the left (blinds, clock, buy-in range, code,
  copy-link, add bot), cashier card fixed on the right (desktop), "você:"
  gone. Copy-link uses a server push_event + tiny JS clipboard listener.
- **Cash-out clarity**: button shows the amount ("sair e sacar 43,25"),
  mid-hand leaves queue with "você sai quando a mão acabar", microcopy
  explains lobby-link vs leaving; rebuy min/max shown.
- **Currency for real**: amounts follow the chosen currency (symbol and
  decimal separator — found a `format/2` bug where the pot mixed "$" with
  comma); active locale/currency highlighted gold in the topbar.
- **De-bootstrapped**: radii 14→8px (cards 8→4px, aged Copag-ish faces),
  real hover states, action bar in a console tray, bolder ＋ sentar seats.
- README rewritten: architecture, engine algorithms, bot heuristics.

## Step 8 — Friends night — next

Expose with `ngrok http 4300` and share `/t/CODE`. Polish backlog from
building, in rough priority: persist ledger to Postgres · host controls
(turn clock length, blinds) · presence (grey out disconnected players) ·
pre-actions (check/fold) · winning hand name at showdown · sounds/vibration
on turn · deal/chip animations · `carvao` theme · en locale.
