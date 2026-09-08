#!/usr/bin/env node
// Content build: authored YAML in, engine payload out (decision 0004).
//
// The YAML is the only thing edited and reviewed. This produces the form the
// engine consumes, because GDScript has no YAML parser and the core does no
// I/O anyway — a loader injects already-parsed data (spec 03).
//
// The output is committed and CI re-runs this to check it is current, so the
// two can never drift apart unnoticed.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const CHART_YAML = join(REPO, "content", "type-chart.yaml");
const NATURES_YAML = join(REPO, "content", "natures.yaml");
const MOVES_DIR = join(REPO, "content", "moves");
const OUT_DIR = join(REPO, "content", "generated");

/// The payload schema. A loader refuses a version it does not know, because
/// refusing to load is recoverable and misreading is not (spec 09, section 9).
const SCHEMA_VERSION = 1;

export function loadChart() {
  return parse(readFileSync(CHART_YAML, "utf8"));
}

export function loadNatures() {
  return parse(readFileSync(NATURES_YAML, "utf8"));
}

/// Reads a directory of one-file-per-entity YAML.
///
/// The filename is the identifier and the file does not repeat it (decision
/// 0025), so the id is attached here — the one place that knows the path.
/// Sorted, so the index and the payload never depend on directory order.
export function loadEntities(directory) {
  const entities = [];

  for (const file of readdirSync(directory).sort()) {
    if (!file.endsWith(".yaml")) continue;
    const parsed = parse(readFileSync(join(directory, file), "utf8")) ?? {};
    entities.push({ id: basename(file, ".yaml"), ...parsed });
  }

  return entities;
}

export function loadMoves() {
  return loadEntities(MOVES_DIR);
}

// Validation is the build's job, not the engine's: a malformed chart must fail
// here, where a human is watching, rather than at runtime.
function validateChart(chart) {
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

  return problems;
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

// A nature is a pair of stats. The rules are structural, so they can be checked
// rather than trusted: five stats pair with five stats, five of the twenty-five
// combinations are neutral, and no pair may appear twice.
function validateNatures(data) {
  const stats = new Set(data.stats.filter((s) => s !== "hp"));
  const problems = [];
  const ids = new Set();
  const pairs = new Set();
  let neutral = 0;

  for (const nature of data.natures) {
    if (ids.has(nature.id)) problems.push(`duplicate nature id "${nature.id}"`);
    ids.add(nature.id);

    if (nature.plus === null || nature.minus === null) {
      if (nature.plus !== null || nature.minus !== null) {
        problems.push(`${nature.id} is half-neutral: one of plus/minus is null`);
      }
      neutral++;
      continue;
    }

    // HP never takes a nature modifier, so a nature naming it is meaningless.
    for (const [role, stat] of [["plus", nature.plus], ["minus", nature.minus]]) {
      if (!stats.has(stat)) problems.push(`${nature.id}: ${role} names "${stat}", not a modifiable stat`);
    }

    const pair = `${nature.plus}/${nature.minus}`;
    if (pairs.has(pair)) problems.push(`duplicate pairing ${pair}`);
    pairs.add(pair);
  }

  const expected = stats.size * stats.size;
  if (data.natures.length !== expected) {
    problems.push(`expected ${expected} natures for ${stats.size} stats, found ${data.natures.length}`);
  }
  if (neutral !== stats.size) {
    problems.push(`expected ${stats.size} neutral natures, found ${neutral}`);
  }

  return problems;
}

const CATEGORIES = new Set(["physical", "special", "status"]);

// Who a move may be aimed at. With two slots a side, "the opponent" stops being
// a single position (spec 09, section 5). The engine consults none of these yet;
// the list grows when a move needs a value it has not got.
const TARGETS = new Set(["single_foe", "single_ally", "self", "all_foes"]);

const ALWAYS_HITS = -1;

// Moves are validated against the type chart, not against a list of their own.
// A move naming a type nobody declared is the kind of typo that survives review
// and produces a move that quietly does neutral damage to everything.
function validateMoves(moves, knownTypes) {
  const problems = [];

  for (const move of moves) {
    const where = `move "${move.id}"`;

    if (!knownTypes.has(move.type)) problems.push(`${where}: unknown type "${move.type}"`);
    if (!CATEGORIES.has(move.category)) problems.push(`${where}: unknown category "${move.category}"`);
    if (!TARGETS.has(move.target)) problems.push(`${where}: unknown target "${move.target}"`);

    if (move.category === "status" && move.power !== 0) {
      problems.push(`${where}: a status move cannot have power`);
    }
    if (move.category !== "status" && move.power <= 0) {
      problems.push(`${where}: a damaging move needs power`);
    }
    if (move.accuracy !== "always" && (move.accuracy < 1 || move.accuracy > 100)) {
      problems.push(`${where}: accuracy must be 1-100 or "always"`);
    }
    if (move.pp <= 0) problems.push(`${where}: pp must be positive`);
  }

  return problems;
}

// `always` becomes a sentinel the engine understands, so the engine never has
// to know that the authored form was a word.
function flattenMove(move) {
  return { ...move, accuracy: move.accuracy === "always" ? ALWAYS_HITS : move.accuracy };
}

/// One payload per entity, plus the index that makes them enumerable.
///
/// Without the index nothing can walk the roster and a loader is reduced to
/// guessing filenames (decision 0025). The directory is wiped first: a deleted
/// entity must not leave its payload behind, since nothing authored that file
/// and nothing else would remove it.
function writeEntities(kind, entities) {
  const dir = join(OUT_DIR, kind);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });

  for (const entity of entities) {
    writeFileSync(join(dir, `${entity.id}.json`), JSON.stringify(entity, null, 2) + "\n");
  }

  const index = { version: SCHEMA_VERSION, ids: entities.map((entity) => entity.id) };
  writeFileSync(join(dir, "index.json"), JSON.stringify(index, null, 2) + "\n");
  return dir;
}

/// Every problem the build found, then it stops.
///
/// One report rather than one per validator: a content pass fixes ten typos in
/// one go or ten times over, and stopping at the first hides the other nine.
function report(problems) {
  if (problems.length === 0) return;

  console.error(`Content build failed, ${problems.length} problem(s):`);
  for (const problem of problems) console.error(`  ${problem}`);
  process.exit(1);
}

function main() {
  const chart = loadChart();
  const natures = loadNatures();
  const moves = loadMoves();
  const knownTypes = new Set(chart.types);

  report([
    ...validateChart(chart),
    ...validateNatures(natures),
    ...validateMoves(moves, knownTypes),
  ]);

  mkdirSync(OUT_DIR, { recursive: true });

  const chartPayload = flatten(chart);
  const chartPath = join(OUT_DIR, "type-chart.json");
  writeFileSync(chartPath, JSON.stringify(chartPayload, null, 2) + "\n");
  const pairs = Object.values(chartPayload.table).reduce((n, row) => n + Object.keys(row).length, 0);
  console.log(`type chart: ${chartPayload.types.length} types, ${pairs} non-neutral pairs -> ${chartPath}`);

  const naturesPath = join(OUT_DIR, "natures.json");
  writeFileSync(naturesPath, JSON.stringify(natures, null, 2) + "\n");
  const neutral = natures.natures.filter((nature) => nature.plus === null).length;
  console.log(`natures:    ${natures.natures.length} entries, ${neutral} neutral -> ${naturesPath}`);

  const movesDir = writeEntities("moves", moves.map(flattenMove));
  console.log(`moves:      ${moves.length} entries -> ${movesDir}/`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
