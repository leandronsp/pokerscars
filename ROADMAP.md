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

## Step 2 — Engine: cards and hand evaluation — next

Pure Elixir, zero processes, zero Ecto. Deck, shuffle (seeded), 7-card
evaluator, hand comparison. Known-hand fixtures + property tests
(`stream_data` enters mix.exs as this step's first commit). Evaluation
tests 1-9 from the engine doc.

## Step 3 — Engine: betting round state machine — later

Four-action union, turn order, street progression, pot + side pots with
refunds. Acceptance criteria: tests 14, 15, 25 and 26 from the engine doc
(the four cases open-source engines get wrong most often).

## Step 4 — Table process — later

GenServer per table (aggregate root): seats, blinds, dealer button, hand
lifecycle, action timers, PubSub broadcasts.

## Step 5 — Lobby and join flow — later

Create table, invite link with room code, join with nickname, pick a seat.

## Step 6 — Table LiveView — later

The screen: per-seat perspective (only your hole cards), community cards,
action bar, real-time updates. Built from `docs/table-design.md`.

## Step 7 — Ledger — later

Buy-in / rebuy / cash-out in integer cents, settlement view (who owes whom).

## Step 8 — Friends night — later

ngrok session with real players; polish pass from what the night teaches.
