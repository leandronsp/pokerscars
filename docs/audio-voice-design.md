# Audio and voice — design

R&D for the Step 8 backlog ("sounds/vibration on turn") and for the open question of
voice chat between friends. Decision-oriented: what we build, what we rejected, what
we postpone. Part 1 ships alone and should; Part 2 depends on nothing in Part 1.

---

# Part 1 — Table sounds

## 1. Decision: synthesis, not bundled assets

**Every sound is synthesized with the Web Audio API. No audio files.**

| | bundled assets | synthesis |
|---|---|---|
| payload | 50–150 KB, 5 requests, cache-busting | 0 bytes, ~150 lines of JS |
| licensing | free poker SFX packs have murky provenance | none to have |
| theming | one asset set per theme, or none | a parameter table, like `--pk-*` |
| realism | wins on a card riffle | ties on everything else |
| tuning | re-export, re-deploy | change a number, reload |

The realism gap is narrower than it sounds: four of the five cues are not recordings
of anything anyway, and the one genuinely sampled sound is a riffle, which we do not
need — we need one card sliding, a filtered noise transient. Theming decides it.
`feltro` and `carvao` already differ by redefining one list of custom properties;
sounds join that list as a parameter set (pitch centre, brightness, decay) instead of
a second asset tree, and a theme that omits them still works, just neutral.

## 2. Where cues come from: diff the projection

`Table.Server` broadcasts one coarse message, `{:table_updated, code}`, and
`TableLive.handle_info/2` answers with `refresh(socket)`. There are **no fine-grained
domain events** to subscribe to, and we are not adding any.

Derive cues instead by diffing the previous `Table.View` against the new one inside
`refresh/1`. The projection already carries every fact the five sounds need
(`hand_no`, `board`, `pot`, per-seat `committed` and `state`, `to_act?`, `result`),
and — the part that makes this the right call — it is **already per-player**, so
"your turn" fires only on the hero's socket without one conditional about identity.
Sound stays a presentation concern; the engine never learns audio exists.

```elixir
# Mount and reconnect are silent: there is no previous view to diff, and
# replaying a hand's worth of sound on a dropped socket is worse than silence.
@spec diff(View.t() | nil, View.t()) :: [map()]
def diff(nil, _new), do: []

def diff(%View{} = old, %View{} = new) do
  [deal(old, new), bet(old, new), turn(old, new), all_in(old, new), win(old, new)]
  |> Enum.reject(&is_nil/1)
  |> suppress_bet_under_all_in()
end
```

| cue | edge detected |
|---|---|
| `deal` | `new.hand_no > old.hand_no` (2 hole cards), or `length(new.board) > length(old.board)` (n board cards) |
| `bet` | `Σ committed` rose; carries the delta and `new.pot` so the sound can scale |
| `turn` | hero's `to_act?` went `false → true` |
| `all_in` | any seat's `state` became `:all_in` |
| `win` | `old.result == nil and new.result != nil` |

Every one is an **edge**, not a level. `result` stays set through the whole 7 s
between-hands pause and `to_act?` through the whole turn, so a level test would
retrigger on every unrelated update. `all_in` suppresses a same-batch `bet`: a shove
already has a sound and it is not a chip clink.

`refresh/1` then pushes at most one event per update — `push_event(socket, "pk:sfx",
%{c: cues})`, only when non-empty. One hook, `TableSound`, on the felt container,
owning no DOM and reacting only to `handleEvent` — the shape the table design doc
already reserved for `TurnAlert`. Vibration and the backgrounded-tab title flash live
in the same hook off the same `turn` cue.

## 3. The five recipes

Two primitives over a shared bus: `burst` is a noise source through a bandpass, `tone`
is an oscillator. Both take a linear attack to `peak` then
`exponentialRampToValueAtTime(0.0001, …)` — exponential ramps cannot target zero, and
the epsilon is the whole trick. The noise buffer is generated once at init (0.4 s of
white noise) and reused by every burst.

```js
bus  = ctx.createGain()                  // user volume, 0..1
comp = ctx.createDynamicsCompressor()    // -18 dBFS, knee 12, ratio 6, atk 3ms, rel 250ms
bus.connect(comp); comp.connect(ctx.destination)
```

The compressor is not polish. With 9 players a deal, a chip and a shove land in the
same 100 ms, and without it that sums past 0 dBFS and clips.

| cue | recipe |
|---|---|
| **deal** | One `burst` per card: bandpass **3000 → 1600 Hz** exponential sweep, **Q 0.7**, attack 4 ms, decay 90 ms, peak **0.30**. Centre jittered ×`rand(0.92, 1.08)` per card, so five board cards are not one card five times. Stagger **40 ms** — the same `--pk-deal-stagger` the visual deal uses, so ear and eye agree. |
| **bet** | `n = clamp(2 + floor(amount / pot * 4), 2, 6)` clinks, each a `burst` at bandpass **4800 Hz** ×`rand(0.85, 1.2)`, **Q 5**, attack 2 ms, decay 45 ms, peak 0.22, offset `rand(12, 40) ms` from the last. Under them one `tone`: sine **170 → 120 Hz**, attack 3 ms, decay 70 ms, peak 0.18, the stack landing on felt. Bet size drives clink count, so the sound carries information. |
| **turn** | Two `tone`s a perfect fifth apart, arpeggiated: sine **880 Hz** (attack 10 ms, decay 380 ms, peak 0.22), then sine **1318.5 Hz** at +85 ms (attack 10 ms, decay 420 ms, peak 0.16). Optional sine **2637 Hz** with the second at peak 0.05 for a bell sheen. Most-heard cue, so it is the quietest and softest-attack of the five. Open fifth, no third: calm, not urgent. |
| **win** | Ascending major triad, `tone` triangle: **523.25 / 659.25 / 783.99 / 1046.5 Hz** at +0/70/140/210 ms, attack 6 ms, decay 400 ms, peaks 0.20/0.20/0.20/0.26, through a shared lowpass at **4500 Hz** to take the edge off the triangle. Under it a `burst` shimmer at +200 ms: bandpass 7500 Hz, Q 1.2, attack 40 ms, decay 600 ms, peak 0.06. Fires at most once per hand, so it may be the richest. |
| **all-in** | Tension, not celebration — the only cue that descends. `tone` sine **180 → 55 Hz** exponential over 700 ms, attack 15 ms, decay 850 ms, peak 0.34. Beneath it two sawtooth `tone`s at **110 Hz and 110.6 Hz** (attack 250 ms, decay 1100 ms, peak 0.07 each) through a lowpass sweeping **900 → 280 Hz**. The 0.6 Hz beat between the detuned pair is the wobble that makes it feel wrong on purpose. ~1.2 s. |

Theme override is a small table: `feltro` uses the values above, `carvao` shifts every
centre frequency up ~15 % and shortens decays ~25 % for a drier, colder read. That is
the entire theming surface. **Dedupe**: no cue plays twice within 60 ms of itself, or
two fast bots machine-gun the chip sound.

## 4. Unlock, mute, volume

**iOS unlock.** An `AudioContext` starts `suspended` on iOS and a later async
`resume()` inside a promise chain is ignored; it must happen inside a real user
gesture. Copy voxquad's `unlock()` verbatim — `resume()` plus a one-sample silent
buffer through `destination` — on a `document`-level `pointerdown` listener with
`{once: true, capture: true}`. Any tap unlocks; in practice that is "sentar", before
any sound could fire.

**Unlock is not permanent.** iOS moves the context to `interrupted` on screen lock,
incoming calls and backgrounding, and there are field reports of Safari 18.x
re-suspending after short idle periods — which a poker table hits constantly, since
30 s can pass between cues. Design defensively rather than diagnose Safari: call
`ctx.resume()` at the top of every cue (a no-op when running) and again on
`visibilitychange`. If `ctx.state !== 'running'` when a cue arrives, **drop it rather
than queue it** — a chime four seconds late is worse than no chime.

**Mute and volume live in `localStorage`, not the session.** The app already has a
server-side prefs pattern (`PrefsController`, locale and currency) and consistency
argued for reusing it, but those switchers are plain `<a href="/prefs?…">` links that
trigger a **full page navigation**: mid-hand that drops the socket, replays the deal
animation, and destroys the unlocked `AudioContext`. Disqualifying. The toggle is
client-only. The topbar renders a stateless button, the hook sets `data-muted` on it
and CSS picks the glyph, inside `phx-update="ignore"` so patches cannot reset an
attribute the server never rendered. Volume is one 0–100 value on `bus.gain`.

**`prefers-reduced-motion` is not the signal** — it is a motion preference, and no
`prefers-reduced-sound` exists to read. The mute toggle is the whole audio
accessibility answer, which is why it sits in the topbar rather than a settings
drawer. Existing reduced-motion rules stay as they are.

**Not doing**: ambient table noise, dealer voice-over, sound on other players' turns,
a per-cue mixer. Each is a volume complaint waiting to happen.

---

# Part 2 — Voice between friends

## 5. The three options

| | mesh + Phoenix signaling | SFU | a WhatsApp call |
|---|---|---|---|
| server media cost | zero (TURN only when P2P fails) | every stream in and out | zero |
| new infrastructure | reuse mendio's coturn | a LiveKit node (2 vCPU / 4 GB min) | none |
| client JS | 300–500 lines, the hard kind | ~150 against an SDK | none |
| works ≥7 players | degrades | yes | yes |
| survives a LiveView reconnect | only if you build it | mostly | trivially |
| runs on a locked phone | no | no | yes |
| seat-bound speaking ring | yes | yes | no |

**The Elixir-native SFU is not on the table.** `membrane_rtc_engine` was archived by
its owner on **12 Nov 2025** with an explicit "will no longer be maintained or
updated", after moving from `fishjam-dev` to `fishjam-cloud` and then stopping.
`ex_webrtc` (Software Mansion) is alive and a real W3C-shaped implementation, but it
is a *peer connection library*, not an SFU — forwarding, simulcast and congestion
control on top of it is a project, not a feature. So "SFU" means running LiveKit next
to the app: a Go server, a Redis, and a second deployment to babysit for a game whose
whole backend is one GenServer per table. Rejected on those grounds, not capability.

## 6. Mesh arithmetic, for audio specifically

The usual "mesh dies past 4 peers" advice is about **video** and does not transfer.
Opus voice runs 24–32 kbps mono; with RTP, SRTP, UDP and IP overhead at 50 packets/s
it costs roughly **45 kbps on the wire** each direction per peer.

| players | connections `N(N-1)/2` | per client | up / down |
|---|---|---|---|
| 2 | 1 | 1 | 45 kbps |
| 6 | 15 | 5 | 225 kbps |
| 9 | 36 | 8 | 360 kbps |

360 kbps is nothing. **Bandwidth is not what breaks audio mesh.** What breaks is
everything else per connection: 8 ICE agents, 8 DTLS handshakes, 8 jitter buffers and
Opus decoders, and above all acoustic echo cancellation running against eight
independently-arriving streams on a phone that is also animating a felt. Plus a
negotiation storm — the 9th player to join fires 8 simultaneous offer/answer exchanges,
every one of which can glare.

**Cap it as a product rule, not an engineering fix: voice is limited to 6 seats.**
Fifteen connections, five per client, comfortably inside a mid-range phone. The 7th
player to press "voz" is told the voice room is full. Same shape of decision as "cash
game only, tournaments are out".

## 7. Signaling: the LiveView socket, not a Channel

The brief assumed a Phoenix Channel per table. **Use `push_event` / `pushEvent` on the
LiveView socket instead**, which is what mendio does in production: `webrtc_offer`,
`webrtc_answer` and `ice_candidate` travel as LiveView events, routed peer-to-peer
through PubSub by a `SignalHandler` module. A Channel means a second socket, a second
auth path (identity is a session cookie read by `EnsurePlayerId`, already resolved on
the LiveView), a `user_socket.js` that is currently commented out, and a roster to
reconcile with the one `TableLive` already has. Signalling is a burst of a few hundred
small messages at join and near-nothing after; the BEAM does not notice.

Per pair, using **perfect negotiation**, with polite/impolite decided by comparing seat
positions — lower position is polite, so glare resolves with no coordinator:

```
seat 3 joins voice → push "voice_join"
  TableLive broadcasts the roster to the table topic
  each existing member's hook creates an RTCPeerConnection for seat 3
  impolite side createOffer → pushEvent "offer"  → server routes → handleEvent
  polite side setRemote/createAnswer → "answer"  → server routes → handleEvent
  both trickle "ice_candidate" until connected
```

The server never parses SDP. It is a router with an allow-list: a signal is forwarded
only between two players at the same table who are both in the voice roster.

## 8. TURN: reuse mendio's coturn, unchanged

**Media never touches the Cloudflare tunnel or ngrok** — those carry HTTPS to Phoenix,
while WebRTC media goes peer-to-peer or via TURN. One exception worth knowing:
`getUserMedia` requires a secure context, so the tunnel's HTTPS is what makes the mic
available at all. A bare `http://192.168.x.x` LAN address silently fails to get a
microphone. Tunnel or localhost only.

STUN alone gets through most home NATs but fails on symmetric NAT, and carrier-grade
NAT on Brazilian mobile data is exactly that — the friend playing from 4G is the case
that needs a relay, and that is half the table. **TURN is mandatory, not a fallback.**

mendio already runs one: `turn.mendio.com.br` → `146.190.151.73`, ports 3478 UDP and
TCP, coturn in `--use-auth-secret` mode, ufw open, provisioned by an Ansible role.
Relay cost when it kicks in is ~360 kbps each way per relayed player on a droplet
already paid for; a full 6-seat table entirely on relay is under 5 Mbps.

- `Mendio.VideoCall.TurnCredentials` is ~40 portable lines — HMAC-SHA1 over
  `"{expiry}:{identifier}"`, base64, 6 h TTL. Copy as `Pokerscars.Voice.TurnCredentials`
  with identifier `"table_{code}_{player_id}"`.
- `use-auth-secret` validates the HMAC and nothing else; it does not care which app
  minted the username, and `realm` only matters for long-term credentials we are not
  using. Sharing the secret across both apps works as-is.
- ICE servers reach the client as a mount assign, not a controller endpoint — mendio
  needed `/webrtc/ice_servers` because its LiveView mounts before the appointment is
  known; ours knows the table at mount.
- Local dev: lift the `coturn` service out of mendio's `docker-compose.yml` verbatim
  (`--static-auth-secret=dev_turn_secret`, `--no-tls`, ports 49152–49200).

## 9. On-table UX

- **A mic button on your own pod only.** Other seats show a mic glyph as status, never
  as a target. Default off: pressing "voz" is what joins and what unlocks the mic.
  Nothing captures audio before an explicit tap.
- **Push-to-talk on `Space`,** held. The table doc reserves `F`, `C`, `R`, `Enter`,
  `Esc`; `Space` is free. Push-to-talk defaults on mobile, open mic on desktop.
- **The speaking ring is client-side and never round-trips.** Poll
  `receiver.getSynchronizationSources()` — it returns `audioLevel` per SSRC with no Web
  Audio graph at all — every 100 ms, with hysteresis (on above 0.05, off below 0.02
  held 400 ms). Chromium and Safari support it; Firefox does not (bugzilla 1363667 is
  long-open), so fall back to one `AnalyserNode` per stream there. Broadcasting
  speaking state would be ~90 re-render messages/second on a 9-seat table. Never.
  The ring itself is a `<span class="pk-voice-ring">` rendered once inside a
  `phx-update="ignore"` wrapper; the hook toggles its class by seat position.
- **A tell is a feature, not a bug** — reacting audibly to your cards is the reason to
  play with voice. But muck and showdown chatter leak real information, so the mic
  drops automatically when you stand up.
- **Backgrounding kills capture on iOS.** Lock the phone and your table-mates stop
  hearing you. No browser fix; say it in the microcopy.

## 10. Recommendation

**Ship Part 1 now. Do not build voice for the next friends night.**

Voice is the highest-effort, lowest-certainty item in the backlog: mendio's hook for a
*1:1* call is **2,913 lines**, and mesh is strictly harder — a per-peer state map,
perfect negotiation, roster reconciliation, and reconnect handling that LiveView
remounts will exercise constantly. Against a project whose entire client-side
JavaScript today is a five-line clipboard listener. Meanwhile a WhatsApp group call is
one tap, works on a locked phone, and has better echo cancellation than anything we
would ship.

So: put a **"voz" button in the topbar that opens a WhatsApp or Discord call**, play
two or three nights, and see whether anyone misses the seat-bound speaking ring.
Knowing *who* is talking, tied to the pod, is the only thing an in-app build buys over
the baseline. If it turns out to matter, Phase 2 below is fully specified and
unblocked.

## Decisions

| Decision | Rejected | Why |
|---|---|---|
| Synthesized SFX, no files | A bundled asset pack | 0 bytes, no licensing question, and themes become a parameter table instead of a second asset tree. |
| Cues by diffing `Table.View` in `refresh/1` | Events from `Table.Server` | The projection already holds every fact the sounds need and is already per-player, so "your turn" is correct for free. |
| Edge detection on every cue | Level checks | `result` and `to_act?` stay set for seconds; a level test retriggers on every unrelated update. |
| Mute/volume in `localStorage` | The existing session-prefs pattern | Those switchers are `<a href>` full navigations; mid-hand that drops the socket and destroys the unlocked `AudioContext`. |
| `ctx.resume()` before every cue | Unlock once at first gesture | iOS re-suspends on lock, calls and idle. `resume()` on a running context is free. |
| Drop late cues when not `running` | Queue them | A chime four seconds after your turn is worse than silence. |
| `DynamicsCompressor` on the master bus | Straight to destination | Deal + chip + all-in inside 100 ms sums past 0 dBFS on a 9-seat table. |
| Mute toggle as the audio a11y control | `prefers-reduced-motion` | It is a motion signal; no sound equivalent exists to read. |
| **Baseline (WhatsApp) for the next session** | Building mesh now | mendio's *1:1* hook is 2,913 lines. The only thing in-app buys is the speaking ring — prove it is missed first. |
| Phase 2 = mesh, capped at 6 voice seats | Uncapped mesh; an SFU | Audio mesh is not bandwidth-bound (360 kbps at 9 peers) but is bound by 8 echo cancellers and jitter buffers on a phone. |
| LiveView `push_event` signaling | A Phoenix Channel per table | The LiveView socket is connected, authenticated by `EnsurePlayerId`, and already knows the roster. Proven in mendio. |
| No Elixir-native SFU | `membrane_rtc_engine`; LiveKit | Archived 12 Nov 2025, explicitly unmaintained. `ex_webrtc` is alive but is a peer library, not an SFU. LiveKit is a second deployment. |
| Reuse mendio's coturn + `TurnCredentials` | A new TURN server; STUN only | Already running, public IP, ufw open; the module is 40 portable lines. STUN alone fails on CGNAT, which is every friend on mobile data. |
| Speaking ring computed client-side | Broadcasting speaking state | ~90 re-render messages/second on a 9-seat table. |

## Implementation checklist

**Phase 1 — sounds (5 steps, ships independently)**

1. `assets/js/table_sound.js`: context, noise buffer, `burst`/`tone`, master bus +
   compressor, `unlock()`, `resume()` guards. No LiveView yet — verify from the console.
2. The five recipes as a parameter table, one function per cue. Tune by ear against a
   real hand in the browser.
3. `PokerscarsWeb.TableLive.Cues.diff/2` with tests. The edge cases are the point:
   mount is silent, a set-and-held `result` fires once, all-in suppresses the chip cue.
4. Wire it: previous view in assigns, `push_event("pk:sfx", …)` in `refresh/1`,
   `TableSound` hook on the felt, vibration and title flash off the `turn` cue.
5. Topbar mute button (`phx-update="ignore"`), volume in `localStorage`, `carvao`
   parameter overrides. Extend `scratchpad/smoke.sh` with the mute toggle and an
   unlock-on-first-tap check.

**Phase 2 — voice, only if the baseline proves insufficient (7 steps)**

1. `Pokerscars.Voice.TurnCredentials` (port from mendio), coturn in
   `docker-compose.yml`, `TURN_*` config in `runtime.exs`.
2. Voice roster in `Table.Server` (`voice: MapSet.t(player_id)`), 6-seat cap,
   join/leave through the same door as every other table command.
3. Signal routing in `TableLive`: three `handle_event`s, three `handle_info`s,
   allow-listed on table and roster. No SDP parsing.
4. `assets/js/voice.js`: `getUserMedia` audio-only with AEC/NS/AGC on, a
   `Map<position, RTCPeerConnection>`, perfect negotiation with polite/impolite by seat
   position, trickle ICE. The hard step — budget it alone.
5. Mic button on the hero pod, push-to-talk on `Space`, mic drops on stand-up.
6. Speaking ring via `getSynchronizationSources()` with an `AnalyserNode` fallback,
   hysteresis, ring inside `phx-update="ignore"`.
7. Reconnect: tear down cleanly on `phx:disconnected`, require one tap to rejoin. Do
   **not** attempt ICE restart — that is where mendio's line count went.


## 11. Decided consent model (2026-07-29 review)

Locked in with Leandro before implementation; overrides anything above
that conflicts.

- **Private (locked) rooms only.** Public and house rooms have no voice,
  period: voice with strangers is the Omegle failure mode this product
  refuses. The public/private line already governs money and chat; voice
  is its third tenant.
- **Explicit opt-in, never automatic.** Joining a table never joins the
  call. A visible "entrar na chamada" action starts local capture; leaving
  the call is one tap and immediate.
- **Seated players only transmit.** Spectators in a private room may
  listen, never speak.
- **Everyone sees everyone's state.** Each seat carries a voice chip:
  in-call/speaking (glow), muted mic, or out of the call. Nobody receives
  audio without every participant being able to tell who is listening —
  the anti-troll invariant.
- **Per-player controls**: mute self, mute any remote player locally,
  per-player volume, leave. All local, no server round-trip.
- **Surface**: a compact expandable top card (voxquad floating-player
  pattern: data-attribute state machine, popover on desktop, bottom-docked
  and non-draggable under 720px). Collapsed = join/leave + master volume;
  expanded = the per-player roster.
- **Transport**: WebRTC mesh ≤ 6, Google STUN now, mendio's coturn later;
  signaling piggybacks the existing LiveView socket. First iteration ships
  STUN-only and states plainly that some networks (CGNAT) will not
  connect until TURN lands.
