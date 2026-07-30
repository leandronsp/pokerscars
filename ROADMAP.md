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

## Round 6 — lobby cards, hero bank, seat etiquette — done

- Lobby regrouped: forms on the left, **open tables as cards** on the right —
  each with a mini felt showing seat occupancy as gold dots, join button,
  eye icon to watch, ✕ to close. Fixed panel size, list scrolls inside.
- **Hero chip bank**: your stack as a chip pile + gold amount beside your
  cards; the pod keeps just your name.
- Seated players no longer see "sentar" invites on the other seats (inert
  placeholders instead).
- Cashier rebuy row no longer touches the card edge; a lone all-in preset
  fills the row instead of floating; receipt note wraps cleanly.
- poker.leandronsp.com confirmed live through the Cloudflare tunnel.
- Smoke battery grew to **55 checks** — it caught the seat-invite regression
  before it shipped.

## Round 7 — smoothness, honesty of the felt, waiting life — done

- **DOM recreation killed with numbers**: a MutationObserver probe measured
  61 nodes added / 47 removed / 4 card subtrees destroyed per action click;
  keyed seat comprehensions (`:key`) + stable seat root ids brought it to
  **0 / 0 / 0**. Action blink, add-bot glitch and river flicker all shared
  this root cause. The smoke battery now asserts zero card kills per click.
- **Chip flight**: pots fly from the felt center to each winner, one wave
  per pot (main first, sides staggered 600ms), keyed per hand so it plays
  exactly once. Reduced-motion disables it.
- **Every pod carries its chip stack** (the floating hero bank retired);
  a lone seated player no longer looks detached.
- **Your folded cards stay face down in front of you**; other players'
  folded cards leave the table, like a real muck.
- **Winner named by nickname always**: a raw player id leaked when the
  winner had already stood up (view resolved names only from live seats);
  the ledger is now the fallback. Regression-tested.
- Status messages got display type; waiting states got life (animated
  ellipsis + a breathing pod while the table waits for players).
- `docs/audio-voice-design.md`: sounds = synthesized Web Audio (no assets),
  cues from diffing the projection client-side; voice = WhatsApp baseline
  first, then a 6-seat WebRTC mesh signaled over the LiveView socket with
  mendio's coturn. Implementation deferred to its own round.

## Round 8 — the phone round — done

Real-iPhone screenshots showed the portrait table unplayable: the board
covered side seats, top seats collided, the hero pod clipped the rim, and
the lobby bled horizontally on iOS. Fixes, all measured on emulated
iPhone 15 (393px) and SE-size (375px) viewports:

- **Seat geometry became CSS classes** (`.pk-slot-N` with `--sx/--sy`), so
  each breakpoint gets its own ring. The portrait ring keeps every seat
  clear of the horizontal board band (sides at sx ±1 above/below it,
  bottom corners empty like real mobile poker clients), computed from the
  actual measured rectangles, not eyeballed.
- Portrait sizing pass: board cards 2.1rem, capped pod width (long bot
  names were silently widening pods into the board), smaller bet pills
  with the "aumentou" tag hidden on phones, tighter pot block, ellipsis
  status in display type.
- `overflow-x: clip` on html/body and `viewport-fit=cover` guard against
  the iOS-only lobby bleed.
- The smoke battery gained a **felt-collision assertion** (part-level
  rect intersection with 2px tolerance, logged offenders) so portrait
  regressions fail CI-style instead of reaching the phone. 60 checks now.

## Round 9 — trust: owners, locks and the play-money line — done

- **Only the creator closes a table** (anyone could grief-close before —
  a hole we shipped ourselves); the lobby shows ✕ only on your own tables
  and the server enforces it regardless.
- **Optional room password**: locked rooms carry a lock badge in the
  lobby; entering (or even watching) asks the password. Unlocking mints a
  **signed capability link** (Phoenix.Token with the table code, 30 days)
  — the same link "copiar link" shares, so friends skip the prompt. The
  password never travels in a URL; revocation = closing the table.
- **Websocket origins locked** to localhost + poker.leandronsp.com
  (check_origin), closing LiveView hijacking from hostile origins.
- **Play-money framing**: the cashier no longer mentions Pix — public
  chips carry no real value. The app is a scorekeeper, never a wallet.
- **AGPL-3.0** license landed; README states the model: free demo with
  fictional chips, paid managed cloud by subscription, never a rake.
- Bots pick the free seat farthest (ring distance) from everyone seated,
  so tables read balanced; PWA standalone metas for fullscreen on iOS.
- `docs/security-trust-design.md` (threat model, fraud between players,
  business precedents) in flight from a research agent.

## Round 10 — the table's diary — done

- **Event log**: the table GenServer keeps a bounded diary (last 50, view
  cuts to 30, newest first) — sits, rebuys, cash-outs, every action (with
  a "tempo esgotado" tag when the clock acted), hand markers, winners.
  Money stays in cents in the domain; the web layer formats per currency.
- **Desktop**: the log card sits below the config card in the left column,
  hand markers as section dividers, one color per event type (win gold,
  sit/rebuy green, cash-out red, raise amber, fold dimmed).
- **Mobile**: nothing renders below the action bar anymore. The config
  card moved into a **kebab drawer** with three tabs (mesa · caixa ·
  eventos); the table head gained a direct **add-bot icon** (creator only,
  server-enforced since round 9) next to the kebab.

## Round 11 — pots split, bots resurrect, cashier confirms — done

- **Live main/side pot split on the felt**: once an all-in layers a settled
  betting round the pot pill splits PokerStars-style ("principal X ·
  lateral Y"), derived from swept contributions only; current-street bets
  still sit in front of the players. Resolution per pot already existed.
- **Bots cannot stall a table anymore**: bot identity is deterministic
  (code + nickname), so a crashed bot resurrects into its own seat
  (`already_seated` now outranks `seat_taken`) and self-kicks to act; the
  bots supervisor got a restart budget wide enough for a whole table dying
  at once. The 45s turn clock stays as the human-grade guarantee.
- **Cashier UX**: rebuy flashes success (immediate or "entra quando a mão
  acabar"); leaving asks for confirmation in a modal with the cash-out
  amount and a mid-hand warning, mobile-first.
- The comanda doubles as the live ranking (already sorted by balance,
  departed players included) — a separate ranking card was built and then
  dropped as redundant.
- **Chaos endpoint** (`GET /dev/kill-bots/:code?n=N`, dev routes only) to
  murder bots on purpose and watch them resurrect — proven live on a
  running table, twice in a row.
- Victory banner collapses to one clause per winner with pots summed
  ("rita leva 250,00"), no more sentence-per-side-pot walls; UI copy swept
  to the você register ("sua mão", "seu apelido").

## Round 12 — the house opens its doors — done

- **Three house rooms** boot with the app, idempotent, fixed codes (CASA01
  a CASA03), owned by the system creator: nobody closes them, nobody
  summons bots into them, links survive restarts. "funciona na minha
  máquina" (0 bots), "pair programming" (2), "daily standup" (5). Tables
  gained a `description` shown on the lobby card under a "mesa da casa"
  badge; house rooms sort first.
- **Lobby right column**: joining by code is now an inline field + button
  above "mesas abertas"; the left column keeps the create card.
- **/dev fenced**: dashboard and chaos tools now demand basic auth
  (user `dev`, password from `DEV_PASSWORD`, fail-closed when unset) —
  they ride the same public tunnel as the app.
- `docs/chat-design.md`: researched moderation design for table chat —
  preset-only vocabulary in public rooms, free text in private rooms,
  seated-only senders, server rate limit, transient messages.

## Round 13 — chat, sounds, presence and a real design system — done

- **Chat** per docs/chat-design.md: preset vocabulary in public rooms
  (abuse unrepresentable), free text in locked rooms, seated-only senders,
  token-bucket throttle, last 10 transient. Mobile: 4th drawer tab + head
  icon + fading ticker over the felt.
- **Right rail**: the desktop side column became one viewport-capped
  tabbed panel (caixa · eventos · papo/chat) with an unread dot — same
  mental model as the mobile drawer, nothing ever cut off. Left column is
  the config card alone; the receipt scrolls internally with sticky header.
- **Sound cues** (TS + WebAudio, voxquad-style services/hook split): your
  turn, you win, hand over. Server decides when (projection diff →
  push_event), client decides whether (localStorage prefs, master +
  per-cue toggles, off by default). No assets, three synth recipes.
- **Presence**: the table monitors each socket; a vanished human dims
  ("caiu") and auto-stands after a 90s grace, mid-hand via the pending
  queue. Reconnection cancels it. Bots also reclaim their seats via
  heartbeat if the table restarts from a crash.
- **Name filter** at the boundary (nicknames + table names): accent and
  leetspeak folding, severe-slur list, conservative substring match.
- **Resilience round**: table supervisor got a crash-wave restart budget,
  house rooms replant themselves every minute, facade maps a dead-pid
  call to table_not_found.
- **Design system**: Playfair Display (real bold, crisp logo) + IBM Plex
  Mono (money, codes, receipt, meta) self-hosted; native selects replaced
  by themed choice chips; full-table "lotada" badge; golden locked cards.
- **Card blink killed for real**: structural churn (bet-pill :if, board
  slots, chat ticker) stopped recreating card SVGs — measured 0 same-patch
  recreations under bot fire; the battery now guards it.
- `/dev` fenced with basic auth; chaos endpoint stays for bot murder.
- docs: bots-learning.md placeholder; voice consent model locked in
  (private rooms only, explicit opt-in, visible listener states).

## Round 14 — the table celebrates and never waits — done

- **Winner celebration on the felt**: every winner's cards swell and glow
  gold (main pot loudest) and the amount won lands as a "+valor" row in
  the winner's own pod. The bar zone keeps the aggregate line and hand
  name; nothing ever covers cards or the board. 12s between hands to
  savor it.
- **Short clock for vanished actors**: a disconnected player's turn runs
  on a 5s clock instead of the full 45s, on top of the 90s auto-stand
  grace. The table never hostages itself to an empty chair.
- Blinds audited against the book: SB left of the button completes the
  half, BB holds the option, heads-up button posts SB and opens — the
  engine already implemented all of it, with explicit tests.
- Battery hardened to 84 checks (winner badge, blink guard re-armed per
  section, state-agnostic sound persistence, 42px tap floors).

## Step 8 — Friends night — next

Expose with `ngrok http 4300` and share `/t/CODE`. Polish backlog from
building, in rough priority: persist ledger to Postgres · host controls
(turn clock length, blinds) · presence (grey out disconnected players) ·
pre-actions (check/fold) · winning hand name at showdown · sounds/vibration
on turn · deal/chip animations · `carvao` theme · en locale.
