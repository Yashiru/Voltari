# 11 — Capture

**Status:** Draft
**Depends on:** specs 03, 04, 07, 09; decisions 0010, 0029
**Not covered by the oracle** — see spec 02, section 3

Throwing a ball takes the turn, so capture happens inside a battle. The rule
that decides it does not belong there.

---

## 1. Where it happens, and what the core is told

Capture is a **command**, resolved by the turn machine like a move or a switch.
It costs the actor its turn and the opponent still acts.

The command carries a **threshold the rules layer already computed**. The core
never learns what a ball is, what a capture rate is, or that species differ: it
receives a number, asks a named question against it, and reports what happened.

That is the same shape the accuracy check already has (spec 04), and it is why
capture can live in a turn without the turn machine growing an opinion about
content — the coupling specs 04 and 06 exist to prevent.

## 2. Three stages, and where each one lives

| Stage | What | Where |
|-------|------|-------|
| 1 | The modified catch rate `a` | L1 |
| 2 | The shake threshold `b` | L1 |
| 3 | Four shake checks against `b` | Core |

    a = floor( ((3·HPmax − 2·HPcur) × rate × ballBonus) / (3·HPmax) × statusBonus )
    b = 1048560 / sqrt(sqrt(16711680 / a))

`rate` is the species' capture rate (spec 09), `ballBonus` the ball's multiplier,
`statusBonus` ×1 with no status and more with one. `a` is capped at 255.

**The split falls between 2 and 3 because that is where content stops being
needed.** Stages 1 and 2 read the ball, the species and the target's condition.
Stage 3 reads one number four times.

**A certain capture needs no special case.** When `a` reaches 255 the rules layer
passes `b = 65536`; a draw runs 0 to 65535, so every check passes. The core has
one path, not two.

## 3. What the numbers actually do

Two levers, both on `a`, and both deliberate:

- **The HP fraction** `(3·HPmax − 2·HPcur) / (3·HPmax)` is 1/3 at full health and
  approaches 1 at a single point. Weakening a target very nearly triples the
  odds.
- **The status bonus** rewards inflicting one.

Together they are what makes the loop *weaken, then throw* rather than *throw
repeatedly*.

**The four shakes are tension, not balance.** Since `b ≈ 65535 · (a/255)^(1/4)`,
four independent checks give back `(a/255)` — the raw ratio. Stage 2 decides how
many shakes are *seen* before a failure, not how often capture succeeds.

This is written down because the algebra is not obvious and someone will
otherwise re-derive it. `16711680 = 255 · 65536` and `1048560 / 16 = 65535`, from
which the quarter-power follows. Measured, the net probability at `a = 128` is
0.503 against a raw ratio of 0.502.

If capture ever needs to be *rarer* than the ratio suggests, the lever is the
exponent — and changing it is a change to this document, not a tuning pass.

## 4. Rounding

Stages 1 and 2 **floor at every division and every root**, in the order written.
Not one rounding at the end: unlike the experience award (decision 0030), the
intermediate values here are integers by construction, and flooring late would
be a different formula rather than a tidier one.

## 5. The shakes reach the log

Each check emits an event; the outcome emits another. The log carries four
shakes and a result, not a verdict.

Spec 07 asks for one event per observable state change, and the reference is what
a player perceives: a shake is a beat, and four of them are four beats. A log too
coarse cannot be re-paced by the UI, and coarseness is not recoverable after the
fact.

## 6. The ball is content

Items have no schema (spec 09, open points). This defines the least that capture
needs and no more:

| Field | Meaning |
|-------|---------|
| `kind` | What the item is; capture reads only `ball` |
| `catch_multiplier` | `ballBonus`, as a ratio |

Other kinds of item extend this when they have a spec to justify their fields.
A schema born of one use will need revisiting; inventing the rest now would be
guessing at systems nobody has designed.

## 7. What a captured creature is

**The same individual.** It is already a creature in the battle, with its levels,
individual values, nature and moves. Capture does not make a new one — it changes
who owns it.

Capture ends the battle on success. Where the creature then goes, and what
happens when there is no room for it, belongs to the party and box system, which
has no spec yet.

## 8. Fidelity, and what stands in for it

Spec 02 puts capture outside the oracle explicitly. There is no differential and
there will not be one.

What replaces it is the same as spec 10 section 9 — hand-derived vectors and
property tests — with one addition capture allows and progression did not: the
net probability has a **closed form**, `a/255`, so the implementation can be
checked against it over the whole range rather than at chosen points.

## 9. Testing obligations

- **Stage 1 at the extremes.** Full health, one point, each status bonus, each
  ball, and the cap at 255.
- **Stage 2 against its closed form**, derived independently rather than by
  re-running the implementation.
- **The net probability is `a/255`** across the range, which is the check that
  the four-shake structure was implemented as tension and not as a second curve.
- **A certain capture is certain**, and it takes the same path as any other.
- **The shake count is the number of checks passed**, so a failure after three
  reads as three.
- Determinism: the same answers give the same capture, shake for shake.

## Open points

- **The status bonus values.** ×2 to ×2.5 is the band; which status sits where is
  design, and it is content the moment statuses are content.
- **A full party.** Capture succeeds with nowhere to put the creature, and
  nothing yet describes where it goes.
- **Capture in a trainer battle.** The reference games refuse it. Nothing here
  does yet, and refusing is a rule that needs stating rather than assuming.
