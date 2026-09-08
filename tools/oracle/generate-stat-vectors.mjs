#!/usr/bin/env node
// Generates stat derivation vectors, and seeds the nature table.
//
// The oracle's stat maths is not plain flooring: its truncation is an unsigned
// 32-bit wrap, and the nature step truncates to 16 bits. Both are reproduced
// rather than approximated — see docs/specs/08-formulas.md section 3.

import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Dex } from "@pkmn/sim";
import { stringify } from "yaml";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const VECTOR_DIR = join(REPO, "tests", "fixtures", "oracle", "procedure", "stats");
const NATURES_YAML = join(REPO, "content", "natures.yaml");

const GEN4 = Dex.forGen(4);
const STATS = ["hp", "atk", "def", "spa", "spd", "spe"];
const MODIFIED_STATS = STATS.filter((s) => s !== "hp");

// The oracle's truncation: an unsigned 32-bit wrap, optionally narrowed.
function tr(num, bits = 0) {
  return bits ? (num >>> 0) % 2 ** bits : num >>> 0;
}

function statOf(stat, base, iv, ev, level, plus, minus) {
  if (stat === "hp") {
    return tr(tr(2 * base + iv + tr(ev / 4) + 100) * level / 100 + 10);
  }
  let value = tr(tr(2 * base + iv + tr(ev / 4)) * level / 100 + 5);
  if (plus === stat) value = tr(tr(value * 110, 16) / 100);
  else if (minus === stat) value = tr(tr(value * 90, 16) / 100);
  return value;
}

// --- nature table: mechanics from the oracle, identifiers ours -------------
//
// Nature NAMES are IP and are not taken from the oracle. Only the mechanical
// pairing is, and the identifiers below are structural placeholders that
// content design will rename later without touching the engine.

function natureId(plus, minus) {
  return plus === null ? `neutral_${minus ?? "none"}` : `${plus}_up_${minus}_down`;
}

function buildNatures() {
  const seen = new Map();

  for (const nature of GEN4.natures.all()) {
    const plus = nature.plus ?? null;
    const minus = nature.minus ?? null;
    // Neutral natures have no plus/minus at all; they collapse to one entry
    // per stat in the oracle's data, so key them by index instead.
    const key = plus === null ? `neutral_${seen.size}` : natureId(plus, minus);
    seen.set(key, { plus, minus });
  }

  const natures = [];
  let neutralIndex = 0;
  for (const [, pair] of seen) {
    const id = pair.plus === null ? `neutral_${STATS[1 + neutralIndex++]}` : natureId(pair.plus, pair.minus);
    natures.push(pair.plus === null ? { id, plus: null, minus: null } : { id, plus: pair.plus, minus: pair.minus });
  }

  return { version: 1, stats: STATS, natures };
}

const NATURES_HEADER = `# Natures — authored content.
#
# A nature is a pair: one stat raised 10%, one lowered 10%. Five are neutral.
# Twenty-five combinations in total.
#
# Identifiers are STRUCTURAL PLACEHOLDERS. Nature names are part of the game's
# IP and are not derived from any reference; renaming these is a content edit
# and touches no engine code.
#
# The mechanical pairings come from @pkmn/sim 0.10.11 gen4.
`;

// --- vectors ---------------------------------------------------------------

const BASES = [1, 5, 45, 80, 100, 130, 180, 255];
const IVS = [0, 15, 31];
const EVS = [0, 1, 3, 4, 100, 252];
const LEVELS = [1, 5, 50, 78, 100];

function buildVectors() {
  const vectors = [];

  for (const stat of STATS) {
    for (const base of BASES) {
      for (const iv of IVS) {
        for (const ev of EVS) {
          for (const level of LEVELS) {
            vectors.push({
              stat,
              base,
              iv,
              ev,
              level,
              neutral: statOf(stat, base, iv, ev, level, null, null),
              raised: statOf(stat, base, iv, ev, level, stat, null),
              lowered: statOf(stat, base, iv, ev, level, null, stat),
            });
          }
        }
      }
    }
  }

  return vectors;
}

// --- stat stages -----------------------------------------------------------
//
// The oracle multiplies by a table entry when the stage is positive and DIVIDES
// by it when negative, flooring either way. Expressed as integer ratios that is
// (2+n)/2 upward and 2/(2+|n|) downward.

const BOOST_TABLE = [1, 1.5, 2, 2.5, 3, 3.5, 4];

function withStage(stat, stage) {
  const clamped = Math.max(-6, Math.min(6, stage));
  return clamped >= 0
    ? Math.floor(stat * BOOST_TABLE[clamped])
    : Math.floor(stat / BOOST_TABLE[-clamped]);
}

function buildStageVectors() {
  const values = [1, 2, 3, 7, 50, 99, 100, 255, 306, 614];
  const rows = [];
  for (const value of values) {
    for (let stage = -6; stage <= 6; stage++) {
      rows.push([value, stage, withStage(value, stage)]);
    }
  }
  return rows;
}

// --- write -----------------------------------------------------------------

const natures = buildNatures();
if (existsSync(NATURES_YAML)) {
  console.warn(`WARNING: ${NATURES_YAML} exists and will be overwritten.\n`);
}
mkdirSync(dirname(NATURES_YAML), { recursive: true });
writeFileSync(NATURES_YAML, NATURES_HEADER + stringify(natures, { lineWidth: 100 }));

const vectors = buildVectors();
mkdirSync(VECTOR_DIR, { recursive: true });
writeFileSync(
  join(VECTOR_DIR, "derivation.json"),
  JSON.stringify(
    {
      oracle: "@pkmn/sim 0.10.11 gen4",
      note: "neutral/raised/lowered are the stat with no nature, a raising nature, a lowering nature.",
      vectors,
      stage_note: "[stat, stage, result] — the stage multiplier applied to a stat.",
      stages: buildStageVectors(),
    },
    null,
    0,
  ) + "\n",
);

const raisedDiffers = vectors.filter((v) => v.raised !== v.neutral).length;
console.log(`natures: ${natures.natures.length} entries (${natures.natures.filter((n) => n.plus === null).length} neutral)`);
console.log(`vectors: ${vectors.length}, of which ${raisedDiffers} where a raising nature changes the result`);
console.log(`stage vectors: ${buildStageVectors().length}`);
console.log(`hp ignores natures: ${vectors.filter((v) => v.stat === "hp").every((v) => v.raised === v.neutral)}`);
