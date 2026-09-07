# 0014 — Mutation testing runs on demand, under a written trigger

**Status:** Accepted
**Date:** 2026-09-07

## Context

Decision 0005 makes mutation testing the real robustness metric, replacing line
coverage as the objective. It is slow by nature: the whole suite is replayed once
per mutant.

## Decision

Mutation testing is **not a CI job** and does not gate a pull request. It is run
on demand.

Because a metric nobody looks at drifts — which is exactly what happened to line
coverage — the trigger is written down rather than left to habit:

> Mutation testing is expected to be run, and its score recorded in the pull
> request, for any change touching the effect system or the turn machine.

## Options rejected

- **Blocking on every pull request.** The strictest gate and the best fit for the
  "run the full CI before opening a PR" standard. But pull requests would take
  tens of minutes once the core grows, and the temptation to bypass it grows with
  the wait.
- **A scheduled daily job.** Keeps pull requests fast while tracking the score
  over time. Rejected in favour of full control over when the cost is paid.

## Consequences

Pull-request feedback stays in the tens of seconds.

The score is a reviewed number rather than an enforced threshold, so it depends
on the trigger convention being honoured. That is a deliberate trade: the
alternative was a gate slow enough to be routinely bypassed.

The speed budget of spec 05 — a core suite under ten seconds — matters more under
this decision, not less: on-demand runs are only usable if they are quick enough
that running one is not a decision in itself.
