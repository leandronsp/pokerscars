# Table chat — design

Decision-oriented R&D for chat at the table. The governing principle is the
same line that already splits money and (soon) voice: **public rooms are for
strangers, private rooms are for friends**. Moderation burden scales with
strangers, so the design removes strangers from the free-text equation
entirely instead of trying to out-filter them.

## 1. The moderation landscape (research summary)

| Approach | How it works | Verdict for us |
|---|---|---|
| Word/phrase lists (LDNOOBW, custom pt-BR) | normalize (case, accents, leetspeak, confusables) then match | Cheap, but pt-BR evasion is trivial ("r4c1st4", spacing, context). Useful as garnish, never as the wall. |
| ML toxicity APIs (Perspective, OpenAI moderation) | score each message remotely | Real cost per message, latency, privacy questions, pt-BR quality uneven. Overkill for a scorekeeper app with no accounts. |
| Rate limiting / shadow throttle | token bucket per player | Solves spam and flooding outright, zero false positives. Always on. |
| Report + human review | users flag, someone reviews | Requires an operations arm this project does not want. Rejected as a load-bearing wall. |
| **Preset-only quick chat** | fixed vocabulary, one tap | Illegal or abusive content is unrepresentable. Zero moderation, zero liability, works in every language. The industry answer for strangers (Rocket League quick chat, Hearthstone emotes, chess.com's default). |

Conclusion: filters do not make strangers safe; vocabularies do. Friends do
not need filters; the social graph is the moderator (whoever invited the
jerk uninvites them).

## 2. The rules

- **Public and house rooms: preset-only.** A curated set of one-tap phrases
  (Gettext msgids, so they localize): "boa mão", "kkkkk", "blefou né",
  "uia", "gg", "vai logo", "pago pra ver", "essa doeu", "respeita",
  "boa noite pessoal", plus a small emoji row (👏 🔥 😂 🫠 🤝). No free text
  anywhere in a room a stranger can reach.
- **Private (locked) rooms: free text**, rate-limited, transient. The room
  owner controls who holds the link; that is the moderation system.
- **Seated players only may send.** Spectators read. Chips in play are the
  skin-in-the-game gate against drive-by trolling.
- **Rate limit server-side**: token bucket per player in the table process,
  burst 3, one message per 2s refill. Applies to presets too (spam-clicking
  "kkkkk" is still spam).
- **Transient by design**: last 30 messages live in the table process and
  die with it. Nothing persists, nothing is logged, nothing to subpoena or
  leak. LGPD posture: no message data at rest.
- **Client-side mute** (later): a local mute list per player, no server
  involvement, no reporting pipeline.
- **Nicknames are the real free-text vector in public rooms** — they render
  for everyone. When house rooms meet real strangers, a normalization +
  wordlist check on nicknames matters more than any chat filter. Tracked in
  the security doc checklist.

## 3. UI

Desktop: a "papo" card under the cashier in the right column, fixed height
(~16rem) with internal scroll so the column never outgrows the felt. Preset
chips render as a wrapping tap row above the (private-room-only) text input.
Messages: nickname in accent, text in body color, newest at the bottom,
auto-scroll pinned unless the reader scrolled up.

Mobile: a fourth tab in the kebab drawer ("papo") plus a chat icon in the
table head that opens the drawer straight on that tab. Liveness without the
drawer: the latest message appears as a transient ticker toast over the top
of the felt (nickname + text, one line, fades after ~4s), so the table
"speaks" even with the drawer closed.

## 4. Domain shape

Chat lives in the table GenServer next to the event diary: a bounded list
of `%{id, nickname, text | {:preset, key}}`, broadcast via the existing
`{:table_updated, code}`. Presets travel as keys, never strings, and the
web layer renders the localized phrase — so the vocabulary is also
tamper-proof (an unknown key renders nothing).
