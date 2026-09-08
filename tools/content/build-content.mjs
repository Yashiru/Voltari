#!/usr/bin/env node
// Content build: authored YAML in, engine payload out (decision 0004).
//
// The YAML is the only thing edited and reviewed. This produces the form the
// engine consumes, because GDScript has no YAML parser and the core does no
// I/O anyway — a loader injects already-parsed data (spec 03).
//
// The output is committed and CI re-runs this to check it is current, so the
// two can never drift apart unnoticed.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const CHART_YAML = join(REPO, "content", "type-chart.yaml");
const OUT_DIR = join(REPO, "content", "generated");

export function loadChart() {
  return parse(readFileSync(CHART_YAML, "utf8"));
}

// Validation is the build's job, not the engine's: a malformed chart must fail
// here, where a human is watching, rather than at runtime.
function validate(chart) {
  const known = new Set(chart.types);
  const problems = [];

  if (known.size !== chart.types.length) problems.push("duplicate entries in `types`");

  for (const [attacking, buckets] of Object.entries(chart.effectiveness)) {
    if (!known.has(attacking)) problems.push(`unknown attacking type "${attacking}"`);

    const seen = new Map();
    for (const [bucket, list] of Object.entries(buckets)) {
      for (const defending of list) {
        if (!known.has(defending)) {
          problems.push(`unknown defending type "${defending}" under ${attacking}.${bucket}`);
        }
        // A pair in two buckets is contradictory, and silently picking one
        // would produce a chart that looks fine and plays wrong.
        if (seen.has(defending)) {
          problems.push(
            `${attacking} vs ${defending} appears in both ${seen.get(defending)} and ${bucket}`,
          );
        }
        seen.set(defending, bucket);
      }
    }
  }

  if (problems.length > 0) {
    console.error("Content build failed:");
    for (const problem of problems) console.error(`  ${problem}`);
    process.exit(1);
  }
}

// Flattened for the engine: attacking type -> defending type -> outcome.
// Absent means neutral, exactly as in the source.
function flatten(chart) {
  const table = {};
  for (const [attacking, buckets] of Object.entries(chart.effectiveness)) {
    const row = {};
    for (const defending of buckets.super_effective ?? []) row[defending] = "super_effective";
    for (const defending of buckets.resisted ?? []) row[defending] = "resisted";
    for (const defending of buckets.immune ?? []) row[defending] = "immune";
    table[attacking] = row;
  }
  return { version: chart.version, types: chart.types, table };
}

function main() {
  const chart = loadChart();
  validate(chart);
  const payload = flatten(chart);

  mkdirSync(OUT_DIR, { recursive: true });
  const path = join(OUT_DIR, "type-chart.json");
  writeFileSync(path, JSON.stringify(payload, null, 2) + "\n");

  const pairs = Object.values(payload.table).reduce((n, row) => n + Object.keys(row).length, 0);
  console.log(`type chart: ${payload.types.length} types, ${pairs} non-neutral pairs -> ${path}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
