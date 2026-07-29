# Security, trust and the money line — design

R&D for running pokerscars as a public, free, play-money demo with private
password rooms, and for the open-source + managed-cloud model. Decision-
oriented: threat → mitigation → status. Much of the MVP cut is already
implemented (creator-only close, password rooms with capability links,
locked websocket origins, play-money cashier copy, AGPL license); this doc
records the reasoning and what remains.

## 1. Threat model

### Content injection / XSS
Nicknames and table names are the only user content rendered to others.
HEEx escapes all interpolation by default; the codebase never uses `raw/1`
on user input. Residual risks: none structural. Social risks remain
(offensive names, names that LOOK like instructions — "envie pix p/ X") —
that is moderation, not injection. **Status: safe by construction; keep the
`raw`-free discipline. Later: a profanity/URL filter on names if the public
demo attracts strangers.**

### Session and identity
Identity is an anonymous `player_id` in the Phoenix session cookie: signed
(tamper-proof), `httpOnly` (no JS access), SameSite=Lax by default. There
is nothing to steal that money depends on — worst case someone loses a
play-money seat. **Status: adequate for the stakes, by design.**

### LiveView websocket hijacking
A hostile page could try opening the LiveView socket cross-origin.
`check_origin` is now locked to `localhost` and `poker.leandronsp.com`.
**Status: done. When the host list grows (self-hosters), it must come from
config/env, not code.**

### Table-code enumeration
Codes are 6 chars over a 31-symbol alphabet ≈ 887M combinations, unlisted
locked rooms are additionally password-gated, and guessing only reaches a
spectator view of a play-money table. **Status: fine. Not worth rate
limiting at this scale.**

### Capability links (locked rooms)
`Phoenix.Token.sign(endpoint, "table-access", code)`, verified at mount
with 30-day max_age. Properties: the password never appears in a URL; the
link admits whoever holds it (that IS the sharing model); revocation =
closing the table (tokens name a code that stops existing); the salt signs
nothing else, so tokens cannot be replayed against other features. Pitfall
accepted: a leaked link admits strangers until the table closes — same
trust level as a leaked password, communicated by the "pede a senha (ou o
link) pra quem criou" copy. **Status: done.**

### Griefing
- *Closing tables*: was open to anyone — now creator-only, enforced
  server-side (`Table.close/2`), UI hides ✕ on tables you don't own.
  **Done.**
- *Bot flooding*: anyone at a table can add bots until it fills. Among
  friends this is a feature. For the public demo: restrict add-bot to the
  creator, or cap bots per table. **Soon.**
- *Seat squatting / multi-accounting*: one browser = one identity; a
  griefer with N private windows can take N seats. Play-money stakes make
  this boring. **Later, if ever.**
- *Create-table spam*: unbounded `Table.create` from one session could
  spawn thousands of processes. Cheap fix: cap open tables per creator
  (e.g. 5) and globally (e.g. 500). **Soon — the one real pre-public gap.**

### Turn-clock abuse
Stalling is already bounded by the configurable action clock with
auto-check/fold. **Done since round one.**

## 2. Fraud between players

Collusion, chip dumping and multi-accounting are unsolvable with code at
this scale — the industry answer is statistical surveillance over massive
volume, which neither exists here nor should. The structural answer:

- **Public rooms are fictional-money by definition.** The cashier says
  "fichas sem valor real"; no settlement instructions, no Pix. Nothing to
  defraud: a cheated pot of play chips costs nothing.
- **Real stakes live in private rooms among people who know each other.**
  The app does not know or care what friends agree outside it. The social
  graph is the anti-fraud system — same as a kitchen-table game.
- **The app never holds money.** No deposits, no withdrawals, no payment
  rails, no rake. It is a scorekeeper. This is simultaneously the security
  posture and the legal posture: in Brazil, operating real-money gaming is
  a licensed activity; a scorekeeper that never touches funds and never
  profits per pot stays firmly outside it. The moment revenue correlates
  with pots (rake, per-hand fees), the product reclassifies. Never cross
  that line.

## 3. Open source and the cloud

**License: AGPL-3.0** (landed). Rationale: anyone can self-host and modify;
anyone offering it as a network service must publish their changes — which
is exactly the protection a hosted-app business wants against silent
closed-source SaaS forks. Precedents running this model: Plausible
(AGPL + managed cloud), Cal.com (AGPL core), Ghost (MIT + hosted, weaker
protection). AGPL does *not* protect the name — register/claim the
**pokerscars trademark** separately so forks must rebrand (this is how
open-core companies keep identity).

**Revenue: subscription for the managed cloud.** Flat monthly price for
hosted private rooms, zero correlation with hands played or pot sizes.
Free public demo = marketing + conscience: fictional chips only.

**Contributions**: DCO (sign-off) over CLA — lighter, keeps AGPL honest,
avoids the "CLA lets the company relicense" distrust. Revisit only if a
dual-licensing business ever matters.

## 4. Decisions

| Decision | Rejected | Why |
|---|---|---|
| Public rooms = fictional chips, no settlement copy | Real-money public rooms | Removes fraud stakes and the gambling-operator classification in one move. |
| Password + signed capability link | Password-only; unlisted-URL-only | The link is how friends actually share; the token names one table and dies with it. |
| Creator-only close, server-enforced | UI-only hiding; anyone closes | UI is a courtesy; the server is the rule. |
| check_origin allowlist | `check_origin: false` | Websocket hijacking is the one cheap LiveView attack; the fix is one line. |
| AGPL-3.0 + managed cloud subscription | MIT; per-transaction fees | AGPL protects the hosted business; rake reclassifies the product as gambling. |
| DCO for contributions | CLA | Friction and trust; no dual-licensing plans. |
| Trust the social graph in private rooms | Anti-collusion tooling | At 9 seats among friends, surveillance is theater. |

## 5. MVP checklist

- [x] HEEx escaping everywhere, no `raw` on user input
- [x] Signed httpOnly session, anonymous ids
- [x] check_origin allowlist
- [x] Creator-only table close
- [x] Optional room password (SHA-256 in-process) + lock badge in lobby
- [x] Capability links via Phoenix.Token, 30-day age, dedicated salt
- [x] Play-money cashier copy, Pix removed
- [x] AGPL-3.0 LICENSE + model in README
- [x] Cap open tables per creator (5) and globally (500)
- [x] Add-bot restricted to the table creator (server-enforced)
- [ ] Host allowlist from env for self-hosters
- [ ] Name filter if the public demo attracts strangers
- [ ] Trademark claim on the name before the cloud launches
