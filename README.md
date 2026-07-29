# pokerscars

No-Limit Texas Hold'em cash games to play with friends — in the browser, on
the phone, over an ngrok link. Real-money settlement happens outside the app:
the cashier keeps the ledger, Pix settles the score.

Founding prompt (pt-BR): [`PROMPT.md`](PROMPT.md) · Living plan:
[`ROADMAP.md`](ROADMAP.md) · Design docs: [`docs/`](docs/)

## Running it

```bash
docker compose up -d     # web on http://localhost:4300, Postgres on 5444
make                     # every target, grouped by context
make check               # the gate: format, warnings-as-errors, credo, dialyzer, tests
```

Everything runs in Docker — no local Elixir needed. To play with friends:
`ngrok http 4300` and share the table link.

## Stack

- **Elixir 1.20 / Phoenix 1.8 / LiveView 1.2** — every screen is a LiveView
  over PubSub; there is no client-side game state and (almost) no JavaScript.
- **Postgres 17** (provisioned; tables currently live in memory).
- **Typing as a discipline**: the 1.20 whole-program type inference plus
  Dialyzer (`:unmatched_returns`) run in `make check`. Structs at every
  boundary, `@spec` on every public function — see `.claude/rules/typing.md`.
- **i18n**: pt-BR is the source locale (msgids), English ships as a Gettext
  catalog; locale and display currency (R$/$/€) are session preferences.

## Architecture

DDD with three bounded contexts under `lib/pokerscars/`, each reachable only
through its public module. Phoenix is a delivery detail.

```
engine/   pure rules: cards, evaluation, betting, pots   (no processes, no Ecto)
table/    one GenServer per table: the aggregate root    (seats, clock, ledger)
bots/     bot players that use the same door humans do
```

**The flow**: a LiveView sends commands through `Pokerscars.Table`; the
table's GenServer applies them to an `Engine.Hand`, broadcasts
`{:table_updated, code}`, and every subscribed socket pulls its own
projection (`Table.View`). The projection is the only place deciding what a
player may see — hole cards never leave the process for anyone else's eyes.

## Engine algorithms

- **Hand evaluation** — categorize-and-compare over the C(7,5) = 21 five-card
  subsets. No lookup tables: at nine seats a showdown costs ~189
  categorizations (microseconds), and readable code beats shipping a 32 MB
  table. Correctness is exhaustive, not sampled: a test evaluates **all
  2,598,960 five-card hands** and asserts the distribution matches the known
  frequency table (40 straight flushes … 1,302,540 high cards).
- **Betting round** — a state machine with four actions only
  (`:fold | :check | :call | {:raise_to, n}`); all-in is a consequence, not
  an action. Two per-seat booleans (`acted_this_round?`, `may_raise?`) carry
  the whole min-raise rule set, including incomplete all-ins not reopening
  the action. A DFS test walks **every legal action sequence** of whole hands
  for small configurations, asserting chip conservation at every leaf.
- **Pots are derived, never accumulated** — recomputed from each seat's total
  contribution on demand. A contribution layer with a single contributor was
  never called and is refunded; that one branch covers both the uncalled bet
  and the biggest-stack excess in multi-way all-ins. Odd chips go to the
  first winner clockwise from the button (TDA rule).
- **Seeded shuffle** — Fisher-Yates over the stateless `:rand` API with the
  seed injected by the table process (`:crypto.strong_rand_bytes` at the
  boundary). The engine stays pure, every hand replays from
  `{seed, button, seats}`, and property tests are deterministic.

## Bot heuristics

Bots (`lib/pokerscars/bots/bot.ex`) are processes that subscribe to the table
like a LiveView does, wait a human-feeling delay, and act on a hand-strength
score with jitter — deliberately beatable, they exist for solo play:

- **Preflop**: pocket pairs score `0.55 + rank/31` (aces ≈ 1.0); unpaired
  hands score by combined rank with a suited bonus.
- **Postflop**: the engine's own evaluator maps the made hand to a fixed
  strength (pair 0.45, two pair 0.65, trips 0.8, straight+ ≥ 0.9).
- **Policy**: ≥ 0.75 pot-raises, ≥ 0.4 calls, checks when free, calls cheap
  bets (≤ stack/8) with anything ≥ 0.3, folds the rest. ±0.075 jitter keeps
  them from being fully predictable. They auto-rebuy when busted.

## Testing

```bash
make test.run                       # whole suite (~2s, includes the exhaustive tests)
make test.watch F=path/to_test.exs  # one file or line
```

ExUnit + StreamData. The suite covers the engine exhaustively (see above),
the table process (projections, turn clock, rebuy queue, muck), the bots
playing unattended, and the LiveViews end to end — two sessions playing a
full hand through the rendered UI, spectator affordances, showdown reveals.
Browser smoke tests run via `agent-browser` before anything ships.
