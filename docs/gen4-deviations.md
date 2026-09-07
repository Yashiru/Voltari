# Deviations from the oracle

Behaviours where Voltari deliberately differs from the gen4 mod of `@pkmn/sim`.

**This list is empty, and that is the intended starting state.** The mechanism
exists and is exercised from day one so that the first real deviation costs
nothing to declare — see `docs/specs/02-fidelity-contract.md`, section 10.

Each entry must state:

1. **Behaviour** — what the oracle does, and what we do instead.
2. **Reason** — why the divergence is worth its cost.
3. **Test** — the test asserting *our* behaviour against the diverging oracle
   vector. Without it the differential is either permanently red, or green by
   accident.

An undeclared divergence is a defect, never a deviation.

---

## Entries

*None.*
