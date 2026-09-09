# 12 — Battle AI

**Status:** Draft
**Depends on:** specs 03, 04, 07, 08; decisions 0010, 0029
**Not covered by the oracle** — a policy is not a rule

What the opponent decides to do, and what it is allowed to know while deciding.

---

## 1. An AI is a decider, not a rule

L0bis (`docs/architecture/layers.md`): it reads a battle and produces commands.
It changes nothing, resolves nothing, and the turn machine cannot tell it apart
from a player.

That separation is not tidiness. It is what makes lockstep networking possible
later — both sides run the same rules and differ only in who chose the commands —
and it is why the AI can be replaced, tested and reasoned about on its own.

**Same purity as the core.** No engine types, no I/O, no clock, no drawn numbers
except through the interface of section 4. An AI that read a clock would make a
replay stop reproducing, and replay is what the fuzzer and the save system both
rest on.

## 2. It sees what a player sees

The AI is handed a **filtered view**, not the battle state: health as a
proportion, no individual values, no effort, no unrevealed moves, no knowledge of
what is on the opposing bench.

Spec 07 already draws this line for the battle log — an opponent sees a
percentage, not exact health. Drawing it differently for the AI would give the
project two answers to one question, and the answer that leaked would be the one
nobody was looking at.

**The view is its own type, not a state with fields blanked.** If it were a
`VltBattleState`, nothing would stop it being passed to the engine, or an AI
holding a real one and never noticing. A separate type makes "the AI cannot
cheat" something the compiler enforces rather than something the reviewer checks.

The cost is real and accepted: a second shape of the battle to build and keep in
step. What keeps it honest is that the view is **derived**, never authored — one
function from state and viewpoint, tested to hide what it claims to hide.

## 3. One implementation, tuned

A single AI, parameterised: how far it looks ahead, how often it takes the best
line rather than a good one, what it thinks a status is worth.

Distinct strategy classes were the alternative, and would read better one at a
time. Rejected because neighbouring strategies share almost everything and would
drift apart — the same evaluation written twice, then differently.

The risk this choice carries is the opposite one: a single path that fills with
branches until "easy" is a set of numbers nobody can picture. Two things hold it
off. **Difficulty is a named preset**, not loose numbers at the call site, so
there is a place to read what "easy" means. And **each parameter must change one
observable behaviour**, demonstrated by a test; a parameter with no test showing
its effect is a parameter nobody can tune.

## 4. It draws, and says so

Departing from the best move — sometimes, deliberately — is what stops an AI
being solved after three battles. So it draws, and it draws the way everything
else in this project does: **named questions to a declared interface**.

A third one, alongside the battle decider and the generation decider. Decision
0029 settled the rule that governs this: one pattern applied to disjoint jobs,
never two mechanisms for one job, and **no question may appear in two
vocabularies**. The meta-test that asserts it extends to cover all three pairs.

Battle, generation and policy are three jobs. A turn asks how the dice fell; a
birth asks what a creature is; an AI asks whether to take the line it found.

## 5. Estimating a move

The AI calls **the same damage code the engine calls**, with a scripted decider:
average roll, no critical. There is one implementation of damage in this project
and the estimate cannot drift from the real thing, because it *is* the real
thing.

This has a consequence worth stating plainly. Assembling a `VltDamageInput` —
offence, defence, the contributed modifiers — currently lives inside the turn
machine, and the AI needs exactly that. **It moves to one place both use.**
Copying it into the AI would be the second implementation this choice was made
to avoid, and it would diverge the first time an effect was added.

What the AI does *not* get is a "what would this move do" query on the core. The
core would gain a public function whose only caller sits above it, which is a
layer paying for a convenience that is not its own.

## 6. What it must never do

- **Read the state instead of the view.** The type prevents it; the rule is
  stated so the type is never widened for convenience.
- **Draw outside the interface.** A replay that stops reproducing is a bug the
  fuzzer can no longer find.
- **Resolve anything.** It may compute what a move would do; it may not apply it.
  Predicting is reading, and the AI reads.

## 7. Testing obligations

- **The view hides what it claims to.** For every field the AI must not see, a
  test that it is absent or reduced. This is the test that stops the view
  quietly widening.
- **Each difficulty parameter changes one observable behaviour**, shown by a
  test. A parameter without one cannot be tuned by anybody.
- **A weak AI loses to a strong one** over a run of battles. Not a property of
  any single choice, and the only check that the difficulty scale means anything.
- **Determinism**: the same view and the same answers give the same command,
  every time.
- **The three vocabularies stay disjoint**, asserted over all three pairs.
- **The estimate matches the engine.** A move the AI predicted, then actually
  played with the same decider, deals what it predicted — which is what says the
  two paths never forked.

## Open points

- **How a trainer names its difficulty.** It is content the moment trainers are
  content, and trainers have no schema yet (spec 09).
- **Switching.** An AI that only ever attacks is a weak AI, but deciding when to
  switch needs a view of the bench, and the view deliberately hides it. What an
  AI may know about its *own* side is not the same question as what it knows
  about yours, and this spec has only answered the second.
- **Doubles targeting.** Choosing between two opponents is a decision singles
  never poses, and the move `target` field (spec 09) is where it starts.
