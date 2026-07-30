# pokerscars

Online poker (No-Limit Texas Hold'em cash game) to play with friends over
ngrok. Phoenix LiveView + Postgres, everything in Docker. Founding prompt:
`PROMPT.md` (pt-BR, historical). Living plan: `ROADMAP.md` — keep it updated
as steps complete.

## Commands

`make` (or `make help`) lists every target, grouped by context.

- `docker compose up -d` (or `make dev.up`) — web on http://localhost:4300,
  Postgres on 5444. First boot compiles everything; `make dev.logs` to watch.
- `make check` — the gate, in Docker: format check, unused deps,
  `compile --warnings-as-errors`, Credo, Dialyzer, tests. Run when a change
  set is done and fix anything it raises.
- `make test.watch F=test/foo_test.exs:12` — one file or line, mid-loop.
- `make types` / `make lint` / `make format` — the individual layers.
- Changing `mix.exs`, `config/*` or `application.ex` requires
  `docker compose restart web` — the code reloader does not cover them.

## MVP decisions

- Cash game NLHE only; tournaments are out.
- Money is a ledger: buy-ins and cash-outs in integer cents, settlement
  happens outside the app (Pix). No payment integration.
- No accounts: host creates a table, shares a link, players join with a
  nickname. Identity is an anonymous session cookie (`EnsurePlayerId` plug).
- Tables and their ledgers persist in Postgres (`Table.Store`): a restart
  restores every open table with its full comanda; anyone seated at the
  crash gets a synthesized cash-out for their last snapshotted stack.
  Seats, hands, chat and events are transient by design.
- Every UI string goes through Gettext; `pt_BR` is the source locale. Never
  hardcode user-facing text.

## Architecture

DDD with bounded contexts — see `.claude/rules/architecture.md`. The typing
discipline (the pyright/pydantic simulation) is `.claude/rules/typing.md`.
Both are mandatory reading before writing code.

Framework guidance (Phoenix 1.8, LiveView, Tailwind v4) lives in the generated
`AGENTS.md`. One override: where it says `mix precommit`, the gate here is
`mix check`.

## Conventions

- Code, comments, tests, docs: English. `PROMPT.md` is the only pt-BR file.
- Every feature lands with tests and is verified in the browser (the /browser
  skill) before it counts as done.
- Update `ROADMAP.md` and this file when a step lands or a decision changes.
