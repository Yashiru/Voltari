#!/usr/bin/env node
// Seeds the authored type chart from the oracle, and generates the vectors that
// verify it.
//
// The YAML it writes is CONTENT: authored, reviewed and versioned from here on
// (decision 0004). This script seeds it once rather than owning it — re-running
// overwrites local edits, which is why it prints a warning when the file exists.
//
// The vectors are the oracle's truth for every pair, so an edit to the chart
// that contradicts Gen 4 fails a test rather than passing review.

import { writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Dex } from "@pkmn/sim";
import { stringify } from "yaml";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const CHART_YAML = join(REPO, "content", "type-chart.yaml");
const VECTOR_DIR = join(REPO, "tests", "fixtures", "oracle", "procedure", "type-chart");

const GEN4 = Dex.forGen(4);

// Showdown indexes by DEFENDING type: damageTaken[attacking] is
// 0 neutral, 1 super effective, 2 resisted, 3 immune.
const NEUTRAL = 0;
const SUPER_EFFECTIVE = 1;
const RESISTED = 2;
const IMMUNE = 3;

// `types.all()` is not filtered by generation: it also returns Fairy and
// Stellar, both marked "Future". Filtering on that marker asks the oracle which
// types existed rather than trusting a remembered list.
const GEN4_TYPE_COUNT = 17;

function realTypes() {
  const types = GEN4.types
    .all()
    .filter((t) => t.name !== "???" && t.isNonstandard !== "Future")
    .map((t) => t.name)
    .sort();

  // Fairy slipping back in would silently violate decision 0003, and a wrong
  // chart looks entirely plausible. Fail instead.
  if (types.length !== GEN4_TYPE_COUNT) {
    throw new Error(
      `Expected ${GEN4_TYPE_COUNT} Gen 4 types, got ${types.length}: ${types.join(", ")}`,
    );
  }
  if (types.some((name) => name.toLowerCase() === "fairy")) {
    throw new Error("Fairy is present; decision 0003 excludes it.");
  }

  return types;
}

const TYPES = realTypes();

function code(attacking, defending) {
  const taken = GEN4.types.get(defending).damageTaken[attacking];
  return taken === undefined ? NEUTRAL : taken;
}

// --- authored chart, sparse: anything absent is neutral -------------------

function buildChart() {
  const effectiveness = {};

  for (const attacking of TYPES) {
    const buckets = { super_effective: [], resisted: [], immune: [] };

    for (const defending of TYPES) {
      switch (code(attacking, defending)) {
        case SUPER_EFFECTIVE:
          buckets.super_effective.push(defending.toLowerCase());
          break;
        case RESISTED:
          buckets.resisted.push(defending.toLowerCase());
          break;
        case IMMUNE:
          buckets.immune.push(defending.toLowerCase());
          break;
      }
    }

    const entry = {};
    for (const [key, list] of Object.entries(buckets)) {
      if (list.length > 0) entry[key] = list;
    }
    if (Object.keys(entry).length > 0) effectiveness[attacking.toLowerCase()] = entry;
  }

  return { version: 1, types: TYPES.map((t) => t.toLowerCase()), effectiveness };
}

const HEADER = `# Gen 4 type chart — authored content, source of truth.
#
# Sparse by design: only non-neutral pairs are listed, and anything absent is
# neutral. Adding a type therefore adds its exceptions instead of touching every
# existing line.
#
# Keys are ATTACKING types; the lists name the DEFENDING types they hit that
# way. No Fairy type (decision 0003).
#
# Seeded from @pkmn/sim 0.10.11 gen4 and verified against its vectors. Run
# \`npm run content:chart\` to render the full matrix for a visual check.
`;

// --- vectors: the oracle's truth for every pair ---------------------------

function exponentOf(attacking, defendingTypes) {
  let exponent = 0;
  for (const defending of defendingTypes) {
    const value = code(attacking, defending);
    if (value === IMMUNE) return null;
    if (value === SUPER_EFFECTIVE) exponent += 1;
    else if (value === RESISTED) exponent -= 1;
  }
  return exponent;
}

function buildVectors() {
  const single = [];
  for (const attacking of TYPES) {
    for (const defending of TYPES) {
      single.push([attacking.toLowerCase(), defending.toLowerCase(), exponentOf(attacking, [defending])]);
    }
  }

  // Every unordered dual-type pairing, so the combination arithmetic — and the
  // rule that immunity wins over any amount of weakness — is exhaustive too.
  const dual = [];
  for (const attacking of TYPES) {
    for (let i = 0; i < TYPES.length; i++) {
      for (let j = i + 1; j < TYPES.length; j++) {
        dual.push([
          attacking.toLowerCase(),
          TYPES[i].toLowerCase(),
          TYPES[j].toLowerCase(),
          exponentOf(attacking, [TYPES[i], TYPES[j]]),
        ]);
      }
    }
  }

  return { single, dual };
}

// --- write ----------------------------------------------------------------

const chart = buildChart();
const vectors = buildVectors();

if (existsSync(CHART_YAML)) {
  console.warn(`WARNING: ${CHART_YAML} exists and will be overwritten.`);
  console.warn("It is authored content — re-seeding discards any edits made to it.\n");
}

mkdirSync(dirname(CHART_YAML), { recursive: true });
writeFileSync(CHART_YAML, HEADER + stringify(chart, { lineWidth: 100 }));

mkdirSync(VECTOR_DIR, { recursive: true });
writeFileSync(
  join(VECTOR_DIR, "pairs.json"),
  JSON.stringify(
    {
      oracle: "@pkmn/sim 0.10.11 gen4",
      note: "[attacking, defending, exponent] — exponent null means immune.",
      single: vectors.single,
      dual: vectors.dual,
    },
    null,
    0,
  ) + "\n",
);

const immune = vectors.single.filter((v) => v[2] === null).length;
console.log(`${TYPES.length} types`);
console.log(`chart:   ${Object.keys(chart.effectiveness).length} attacking types with exceptions`);
console.log(`vectors: ${vectors.single.length} single, ${vectors.dual.length} dual, ${immune} immunities`);
