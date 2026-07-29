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

## Step 1 — R&D: poker engine + table design — in progress

Parallel research lines (subagents), each producing a doc under `docs/`:

- **How a poker engine works** — hand evaluation algorithms, betting round
  state machine, pot and side-pot math, dealer button/blinds rotation, what
  open-source engines got right. Output: `docs/engine-design.md`.
- **Table UI/UX** — table layouts that read well on phone + desktop, card
  design, action buttons (fold/check/call/raise sizing), chip/pot animation,
  turn indication, themes. What voxquad/mendio/pitchr teach (LiveView hooks,
  client-autonomous islands, CSS custom-property themes). Output:
  `docs/table-design.md`.

Decisions fold back into this file and `.claude/rules/architecture.md`.

## Step 2 — Engine: cards and hand evaluation — later

Pure Elixir, zero processes, zero Ecto. Deck, shuffle, 7-card evaluator,
hand comparison. Property tests + known-hand fixtures.

## Step 3 — Engine: betting round state machine — later

Actions (fold/check/call/bet/raise/all-in), turn order, street progression
(preflop → flop → turn → river → showdown), pot + side pots.

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
