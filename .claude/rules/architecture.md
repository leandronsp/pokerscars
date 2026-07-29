# Architecture

DDD, hexagonal-lite: the domain is pure Elixir, Phoenix is a delivery detail.
The detailed designs are `docs/engine-design.md` (structs, state machine,
mandatory tests) and `docs/table-design.md` (layout, components, tokens,
themes) — read the relevant one before implementing in its area.

## Bounded contexts

One directory per context under `lib/pokerscars/`, one public module each:

- `engine/` — the poker rules: deck, hand evaluation, betting rounds, pot and
  side-pot math. Pure functions, no processes, no Ecto, no side effects. The
  most-tested code in the repo.
- `table/` — a running table: seats, hand lifecycle, turn timers. One
  GenServer per table is the aggregate root; it holds engine state, applies
  commands, emits events.
- `ledger/` — buy-ins and cash-outs in integer cents, settlement math.

Contexts appear here as they are born; keep the list current.

## Rules

- Contexts talk through their public module (`Pokerscars.Engine`, ...), never
  by reaching into another context's internals.
- The aggregate root owns all mutation: commands in, events/new state out.
  Nothing else mutates a running table.
- LiveViews render state and forward commands. No game rules in the web layer.
- The table process broadcasts via PubSub; LiveViews subscribe and re-render.
  Each player sees their own projection (hole cards are per-seat secrets —
  never broadcast another seat's cards to a socket).
- Components (cards, chips, seats, action bar) live in
  `lib/pokerscars_web/components/`, reusable and theme-aware.
