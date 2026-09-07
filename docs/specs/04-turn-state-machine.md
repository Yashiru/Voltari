# 04 — Turn state machine

**Status:** Draft
**Depends on:** specs 02, 03; decisions 0001, 0009, 0010, 0011

Defines *when* things happen: the phases of a turn, how actions are ordered, and
where the effect system is allowed to intervene.

It does not define how effects bind to those points (spec 06), the event
vocabulary (spec 07), or any formula (spec 08).

---

## 1. Resolution API

Turn resolution cannot assume all input is available up front: when a creature
faints, a replacement must be chosen, and that choice depends on what just
happened.

```
resolve(state, commands, decider) -> Outcome

Outcome =
    Complete(state', log)
  | NeedsInput(state', log, request)
```

On `NeedsInput`, the caller supplies the requested commands and calls `resolve`
again. **The position within the turn is part of the battle state**, and the
state remains serialisable at every suspension point.

Three things fall out of that, and all three would be expensive to retrofit:

- A battle can be saved mid-turn.
- PvP gets its request/response cycle for free — it is the same shape a network
  protocol needs.
- Replay stays total rather than partial.

`resolve` never mutates its input state (decision 0011).

## 2. Command validation

The core **validates and rejects**. An illegal command — switching to a fainted
creature, a move the creature does not know, an invalid target — returns an
explicit error. It never produces a corrupted state and never silently
substitutes something else.

This is not defensive decoration. In PvP the commands arrive from the network and
are not trustworthy, and the fuzzer needs to submit malformed input without
"crash" and "refusal" being indistinguishable.

**Legality is not the same as game rules.** Having no PP left yields Struggle;
that is a rule, resolved during execution, not a rejected command. Validation
answers *"was this command well-formed and permitted at submission time?"*
— nothing more.

## 3. Phases

```
  command collection            (outside resolution)
  ─────────────────────────────────────────────────
  turn start
  action ordering
  action execution loop
      per action:  can-act checks
                   move execution
  residual
  faint resolution              (may suspend: NeedsInput)
  turn end
```

Move execution decomposes into the points where most effects intervene:

```
  target resolution
  veto checks            protect, immunity, semi-invulnerable
  accuracy check
  damage computation
  damage application
  secondary effects
  post-hit               contact, recoil, drain
  faint check
```

### The turn machine hardcodes no effect

This is the load-bearing rule of the whole design.

The turn machine defines **anchors** and drains an ordered queue at each one. It
never names an individual effect, never branches on one, and never knows which
exist. Which effects run at an anchor, and in what order, is declared by the
effects themselves (spec 06).

The end-of-turn residual order is the clearest case: it is a long, precise,
fidelity-critical sequence. It lives as **per-effect declared priority**, not as
a sequence of calls in the turn machine. The same holds for can-act checks
(sleep, flinch, confusion and the rest), which are ordered effects, not `if`
branches.

Without this rule, every new mechanic edits the turn machine, and the turn
machine becomes the spaghetti the architecture exists to prevent.

## 4. Action ordering

Order is computed **once**, after commands are locked, from: action kind, then
priority bracket, then speed, then speed tie (resolved through the decider of
spec 03, never by iteration order).

Once built, the queue admits **cancellation and interception, never reordering**.
An action whose actor has fainted or flinched is cancelled; some mechanics insert
an action ahead of another. A speed change mid-turn does not resort what remains.

The exact ordering rules are settled by the oracle (spec 02), not by this
document. What this document fixes is the *shape*: a queue built once, mutable
only by cancellation and insertion.

## 5. Suspension points

Only `faint resolution` suspends today, requesting replacements. The request
carries which side and which slots must answer.

The mechanism is defined generically — `NeedsInput` names a request kind — so a
second kind can be added later without changing the API shape. It is not
generalised further than that on speculation.

## 6. Determinism

Given the same state, the same commands and the same decider, resolution produces
the same result and the same log, bit for bit. This is asserted directly by
property-based tests (spec 05).

The obligation from spec 03 applies throughout: no decision may depend on
iteration order over an unordered collection, on object identity, or on anything
unreachable from the state and the decider.

---

## Open points

- Whether the residual order is a single flat priority space or one per residual
  category is decided with spec 06, once effect declarations have a shape.
- The action-kind ordering (switch versus item versus move) is a fidelity
  question and gets its vectors from the oracle before implementation.
