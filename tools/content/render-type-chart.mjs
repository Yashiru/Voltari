#!/usr/bin/env node
// Renders the authored chart as a full matrix, for verification at a glance.
//
// The source is sparse so that diffs stay readable; this is the other half of
// that trade — the view a human checks against a reference, without the sparse
// form having to carry 190 neutral entries to make it possible.
//
// Rows are ATTACKING types, columns DEFENDING.

import { loadChart } from "./build-content.mjs";

const SYMBOL = { super_effective: "2", resisted: "½", immune: "0", neutral: "·" };

const chart = loadChart();
const types = chart.types;
const width = Math.max(...types.map((t) => t.length));

function outcome(attacking, defending) {
  const buckets = chart.effectiveness[attacking];
  if (buckets === undefined) return "neutral";
  if ((buckets.super_effective ?? []).includes(defending)) return "super_effective";
  if ((buckets.resisted ?? []).includes(defending)) return "resisted";
  if ((buckets.immune ?? []).includes(defending)) return "immune";
  return "neutral";
}

// Column headers, written vertically so each column stays one character wide.
const headerRows = Math.max(...types.map((t) => t.length));
for (let row = 0; row < headerRows; row++) {
  const letters = types.map((t) => (t[row] ?? " ").toUpperCase()).join(" ");
  console.log(`${" ".repeat(width + 2)}${letters}`);
}
console.log(`${" ".repeat(width + 2)}${"-".repeat(types.length * 2 - 1)}`);

const counts = { super_effective: 0, resisted: 0, immune: 0, neutral: 0 };
for (const attacking of types) {
  const cells = types.map((defending) => {
    const result = outcome(attacking, defending);
    counts[result]++;
    return SYMBOL[result];
  });
  console.log(`${attacking.padStart(width)}  ${cells.join(" ")}`);
}

console.log(
  `\n2 super effective  ½ resisted  0 immune  · neutral` +
    `\n${counts.super_effective} / ${counts.resisted} / ${counts.immune} / ${counts.neutral}` +
    ` out of ${types.length * types.length} pairs`,
);
