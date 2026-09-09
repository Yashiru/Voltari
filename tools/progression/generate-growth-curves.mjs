#!/usr/bin/env node
// Seeds the authored growth curves from PokéAPI.
//
// Progression has no oracle: spec 02 limits @pkmn/sim to battle mechanics, and
// Showdown models no experience at all. So a curve cannot be differentially
// tested, and spec 10 section 9 asks instead for a published source recorded
// beside the numbers. This is that source, fetched once.
//
// The YAML it writes is CONTENT: authored, reviewed and versioned from here on
// (decision 0004). This seeds it rather than owning it — re-running overwrites
// local edits, so it refuses when the file already exists.
//
// **The tables are verified, not trusted.** PokéAPI publishes both the formula
// and the level table for each curve, so the four closed-form curves are checked
// against their own formula at levels 2 to 100. The two piecewise ones have no
// closed form to check against and get structural checks only; the script says
// which it did, because a verification nobody can see the shape of is worth
// little.
//
// Fetched once and cached here, which is what PokéAPI's fair use policy asks:
// "Locally cache resources whenever you request them." The test suite stays
// hermetic — it reads the committed YAML, never the network (spec 02, section 7).
//
// Data: PokéAPI (https://pokeapi.co). Mechanical tables only; no names cross
// over, in keeping with the clean room rule.
//
// Usage: node tools/progression/generate-growth-curves.mjs [--force]

import { writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT = join(REPO, "content", "growth-curves.yaml");
const API = "https://pokeapi.co/api/v2/growth-rate";

const MAX_LEVEL = 100;

// Their identifier on the left, ours on the right. The mapping stays here, on
// the tooling side, exactly as the Showdown one does — content carries our
// vocabulary only.
//
// `check` is the closed form the table must reproduce, where it has one. The two
// piecewise curves are deliberately null rather than transcribed: writing them
// out from memory would be the unverified assertion this script exists to avoid.
const CURVES = [
  { theirs: "slow", ours: "slow", check: (n) => Math.floor((5 * n ** 3) / 4) },
  { theirs: "medium", ours: "medium_fast", check: (n) => n ** 3 },
  { theirs: "fast", ours: "fast", check: (n) => Math.floor((4 * n ** 3) / 5) },
  {
    theirs: "medium-slow",
    ours: "medium_slow",
    check: (n) => Math.floor((6 / 5) * n ** 3 - 15 * n ** 2 + 100 * n - 140),
  },
  { theirs: "slow-then-very-fast", ours: "erratic", check: null },
  { theirs: "fast-then-very-slow", ours: "fluctuating", check: null },
];

async function fetchCurve(name) {
  const response = await fetch(`${API}/${name}/`);
  if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`);
  return response.json();
}

/// Structural checks, which need no outside knowledge and catch a truncated or
/// reordered fetch: one entry per level, starting at zero, strictly increasing.
function structuralProblems(curve, levels) {
  const problems = [];

  if (levels.length !== MAX_LEVEL) {
    problems.push(`${curve.ours}: ${levels.length} levels, expected ${MAX_LEVEL}`);
    return problems;
  }

  for (let index = 0; index < levels.length; index++) {
    const entry = levels[index];
    if (entry.level !== index + 1) problems.push(`${curve.ours}: level ${entry.level} out of order`);
    if (!Number.isInteger(entry.experience)) {
      problems.push(`${curve.ours}: level ${entry.level} has a non-integer total`);
    }
    if (index > 0 && entry.experience <= levels[index - 1].experience) {
      problems.push(`${curve.ours}: level ${entry.level} does not exceed the one before it`);
    }
  }

  if (levels[0].experience !== 0) problems.push(`${curve.ours}: level 1 is not zero`);
  return problems;
}

/// The strong check: the published table against the published formula.
///
/// From level 2. Level 1 is zero by definition — a creature starts there and has
/// earned nothing — and the cubics do not agree with that: `medium_slow` gives
/// -54 at level 1 and `slow` gives 1. The tables are right and the formula simply
/// does not govern the first level. Checking found that; remembering would not
/// have.
function formulaProblems(curve, levels) {
  if (curve.check === null) return [];

  const problems = [];
  for (const entry of levels.slice(1)) {
    const expected = curve.check(entry.level);
    if (entry.experience !== expected) {
      problems.push(
        `${curve.ours}: level ${entry.level} is ${entry.experience}, formula gives ${expected}`,
      );
    }
  }
  return problems;
}

function render(curves) {
  const lines = [
    "# Experience curves — authored content, source of truth.",
    "#",
    "# Cumulative experience required to REACH each level, so level 1 is always 0.",
    "# A creature's curve is named by its species (spec 09).",
    "#",
    "# Progression has no oracle: @pkmn/sim covers battle mechanics only and models",
    "# no experience at all (spec 02, section 3). These tables therefore come from a",
    "# published source rather than from a differential — PokéAPI (https://pokeapi.co),",
    "# seeded by `npm --prefix tools run content:curves`.",
    "#",
    "# Verified rather than trusted: the four closed-form curves were checked against",
    "# their own published formula at levels 2 to 100, and all six against structure —",
    "# one entry per level, starting at zero, strictly increasing. Level 1 is exempt",
    "# because it is zero by definition and the cubics disagree with that: medium_slow",
    "# gives -54 there. The two piecewise curves have no closed form here on purpose;",
    "# transcribing one from memory is the unverified assertion this avoids.",
    "#",
    "# Identifiers are ours. The mapping to the source's own names stays in the tool.",
    "version: 1",
    "curves:",
  ];

  for (const { curve, levels, verified } of curves) {
    lines.push(`  # ${verified}`);
    lines.push(`  ${curve.ours}:`);
    for (const entry of levels) lines.push(`    - ${entry.experience}`);
  }

  return lines.join("\n") + "\n";
}

async function main() {
  if (existsSync(OUT) && !process.argv.includes("--force")) {
    console.error(`${OUT} already exists. It is content now; pass --force to reseed it.`);
    process.exit(1);
  }

  const problems = [];
  const collected = [];

  for (const curve of CURVES) {
    const data = await fetchCurve(curve.theirs);
    const levels = [...data.levels].sort((a, b) => a.level - b.level);

    const structural = structuralProblems(curve, levels);
    const formula = formulaProblems(curve, levels);
    problems.push(...structural, ...formula);

    collected.push({
      curve,
      levels,
      verified:
        curve.check === null
          ? "structure only: piecewise, no closed form to check against"
          : "checked against its published formula, levels 2 to 100",
    });

    const how = curve.check === null ? "structure" : "formula + structure";
    console.log(`${curve.ours.padEnd(12)} ${levels.at(-1).experience.toString().padStart(9)} at 100  (${how})`);
  }

  if (problems.length > 0) {
    console.error(`\nRefusing to write, ${problems.length} problem(s):`);
    for (const problem of problems) console.error(`  ${problem}`);
    process.exit(1);
  }

  writeFileSync(OUT, render(collected));
  console.log(`\nwrote ${collected.length} curves -> ${OUT}`);
}

await main();
