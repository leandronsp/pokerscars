# Learning bots — future research placeholder

NOT for the current round. This file frames the research to do when we get
here; nothing below is decided or implemented.

## The idea

Bots that improve as they play: reinforcement learning over the hands the
tables already produce, replacing (or augmenting) the fixed hand-strength
heuristic in `lib/pokerscars/bots/bot.ex`.

## Directions to explore later

- **CFR family vs deep RL.** Counterfactual Regret Minimization (and MCCFR)
  is the classical poker answer (Libratus/Pluribus lineage) — strong theory
  for imperfect-information games, heavy abstraction work. Deep RL
  (self-play policy gradients, NFSP, Deep CFR) trades theory for
  generality. For beatable-but-fun house bots, a small policy net trained
  by self-play may be plenty; solving poker is explicitly not the goal.
- **State encoding.** Hole cards + board (card embeddings or one-hot),
  pot odds, stack-to-pot ratio, position, betting history of the hand.
  The `Table.View` projection is already the honest information set a
  player sees — the natural feature source.
- **Elixir integration.** Nx/Axon for in-BEAM inference (no extra service);
  training offline (Axon or Python) with weights shipped as artifacts.
  Alternative: a sidecar inference service — more moving parts, rejected
  by default until proven necessary.
- **Difficulty dial.** Whatever learns must stay tunable: house rooms want
  approachable bots. Mix a learned policy with the current heuristic by a
  temperature/blend parameter per room.

## What the tables would need to log

Nothing is persisted today (by design). Training data would need per-hand
records: seed, seats, button, action sequence, showdown result — exactly
the replay tuple the engine already supports (`{seed, button, seats}` plus
actions). A future `hands` table in Postgres covers it; ties into the
persistence work.

## Open questions

- Play-money incentives produce degenerate data (people shove any two).
  Filter to hands from "serious" tables? Train purely by self-play?
- Compute budget and where training runs (local? CI job?).
- How to evaluate "fun to play against" beyond winrate.
