#!/usr/bin/env node
// Content build: authored YAML in, engine payload out (decision 0004).
//
// The YAML is the only thing edited and reviewed. This produces the form the
// engine consumes, because GDScript has no YAML parser and the core does no
// I/O anyway — a loader injects already-parsed data (spec 03).
//
// The output is committed and CI re-runs this to check it is current, so the
// two can never drift apart unnoticed.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync } from "node:fs";
import { dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";

/**
 * Reads one YAML file, and says which one when it will not parse.
 *
 * The library's own error names a line and a column and not a file, which for a
 * build that reads forty of them is a stack trace and a search. The tab case is
 * called out by name because it is the one that arrives on its own: an editor
 * set to indent with tabs rewrites a file on save, and YAML forbids a tab as
 * indentation, so a file nobody edited stops parsing.
 */
function readYaml(path) {
  try {
    return parseYaml(readFileSync(path, "utf8"));
  } catch (error) {
    const where = error.linePos?.[0] ? ` line ${error.linePos[0].line}` : "";
    if (error.code === "TAB_AS_INDENT") {
      throw new Error(
        `${path}${where}: indented with a tab. YAML allows only spaces — ` +
          `check your editor's "convert indent on save".`,
      );
    }
    throw new Error(`${path}${where}: ${error.message}`);
  }
}

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const CHART_YAML = join(REPO, "content", "type-chart.yaml");
const NATURES_YAML = join(REPO, "content", "natures.yaml");
const CURVES_YAML = join(REPO, "content", "growth-curves.yaml");
const MOVES_DIR = join(REPO, "content", "moves");
const SPECIES_DIR = join(REPO, "content", "species");
const ITEMS_DIR = join(REPO, "content", "items");
const ENCOUNTERS_DIR = join(REPO, "content", "encounters");
const PRESENTATION_DIR = join(REPO, "content", "presentation");
const OUT_DIR = join(REPO, "content", "generated");

/// The payload schema. A loader refuses a version it does not know, because
/// refusing to load is recoverable and misreading is not (spec 09, section 9).
const SCHEMA_VERSION = 1;

export function loadChart() {
  return readYaml(CHART_YAML);
}

export function loadNatures() {
  return readYaml(NATURES_YAML);
}

export function loadCurves() {
  return readYaml(CURVES_YAML);
}

/// Reads a directory of one-file-per-entity YAML.
///
/// The filename is the identifier and the file does not repeat it (decision
/// 0025), so the id is attached here — the one place that knows the path.
/// Sorted, so the index and the payload never depend on directory order.
export function loadEntities(directory) {
  const entities = [];
  // A kind with nothing authored yet is not an error. Presentation is the first:
  // its manifests arrive with the fakemon, and until then the machinery is
  // proven on fixtures rather than on content (spec 16).
  if (!existsSync(directory)) return entities;

  for (const file of readdirSync(directory).sort()) {
    if (!file.endsWith(".yaml")) continue;
    const parsed = readYaml(join(directory, file)) ?? {};
    entities.push({ id: basename(file, ".yaml"), ...parsed });
  }

  return entities;
}

export function loadMoves() {
  return loadEntities(MOVES_DIR);
}

export function loadSpecies() {
  return loadEntities(SPECIES_DIR);
}

export function loadItems() {
  return loadEntities(ITEMS_DIR);
}

export function loadEncounters() {
  return loadEntities(ENCOUNTERS_DIR);
}

export function loadPresentation() {
  return loadEntities(PRESENTATION_DIR);
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

// The least an item needs for capture to work, and no more (spec 11, section 6).
// Other kinds extend this when they have a spec to justify their fields.
const ITEM_KINDS = new Set(["ball"]);
const MIN_CATCH_MULTIPLIER = 0.1;
const MAX_CATCH_MULTIPLIER = 255;

function validateItems(items) {
  const problems = [];

  for (const item of items) {
    const where = `item "${item.id}"`;

    if (!ITEM_KINDS.has(item.kind)) {
      problems.push(`${where}: unknown kind "${item.kind}"`);
      continue;
    }

    if (item.kind === "ball") {
      const bonus = item.catch_multiplier;
      if (typeof bonus !== "number" || bonus < MIN_CATCH_MULTIPLIER || bonus > MAX_CATCH_MULTIPLIER) {
        problems.push(
          `${where}: catch_multiplier must be ${MIN_CATCH_MULTIPLIER} to ${MAX_CATCH_MULTIPLIER}`,
        );
      }
    }
  }

  return problems;
}

// The animation vocabulary (spec 16, section 4). It lives here *and* in
// ClipMap, which is two lists that could drift — so the build emits it and an
// engine-side meta-test asserts the two agree. Neither side can quietly win.
const SLOTS = {
  battle: ["enter", "idle", "attack_physical", "attack_special", "hurt", "faint"],
  field: ["field_idle", "walk", "run"],
  companion: ["companion_idle", "happy", "unhappy", "eat"],
};
const EVERY_SLOT = new Set(Object.values(SLOTS).flat());

// A fallback is written, never inferred: `hurt: use idle` is a decision and an
// omission is not (decision 0047).
const FALLBACK = /^use\s+(\S+)$/;

/// Where the quarantined models live (decision 0027).
const QUARANTINE = "res://game/assets/placeholders/";

/// Whether a scene is really there.
///
/// A path under the quarantine is accepted without looking, and that is not a
/// hole: decision 0027 guarantees those files are on exactly one machine, so a
/// check here would fail on every clone but one and say nothing true. What it
/// still catches is the ordinary case — a fakemon whose scene was renamed.
function existsSince(path) {
  if (path.startsWith(QUARANTINE)) return true;
  return existsSync(join(REPO, path.slice("res://".length)));
}

function validatePresentation(entries, knownSpecies) {
  const problems = [];

  for (const entry of entries) {
    const where = `presentation "${entry.id}"`;

    if (!knownSpecies.has(entry.id)) problems.push(`${where}: no such species`);

    if (typeof entry.scene !== "string" || !entry.scene.startsWith("res://")) {
      problems.push(`${where}: scene must be a res:// path`);
    } else if (!existsSince(entry.scene)) {
      problems.push(`${where}: scene "${entry.scene}" is not there`);
    }
    if (typeof entry.height !== "number" || entry.height <= 0) {
      problems.push(`${where}: height must be a positive number of metres`);
    }

    const clips = entry.clips ?? {};
    if (typeof clips !== "object" || Array.isArray(clips)) {
      problems.push(`${where}: clips must be a mapping of slot to takes`);
      continue;
    }

    const real = new Set();
    for (const [slot, takes] of Object.entries(clips)) {
      if (!EVERY_SLOT.has(slot)) {
        problems.push(`${where}: "${slot}" is not a slot`);
        continue;
      }
      if (Array.isArray(takes)) {
        if (takes.length === 0) problems.push(`${where}: ${slot} lists no takes`);
        real.add(slot);
        continue;
      }
      if (typeof takes !== "string" || !FALLBACK.test(takes)) {
        problems.push(`${where}: ${slot} must be a list of takes or "use <slot>"`);
      }
    }

    // Checked after the pass, so a fallback may name a slot declared later in
    // the file — the order somebody writes a manifest in is not a rule.
    for (const [slot, takes] of Object.entries(clips)) {
      const fallback = typeof takes === "string" && FALLBACK.exec(takes);
      if (!fallback) continue;
      if (fallback[1] === slot) {
        problems.push(`${where}: ${slot} falls back to itself`);
      } else if (!real.has(fallback[1])) {
        // A chain of fallbacks resolves to nothing, and nothing is what plays.
        problems.push(`${where}: ${slot} falls back to "${fallback[1]}", which has no takes`);
      }
    }

    for (const field of ["extras", "stow"]) {
      const list = entry[field] ?? [];
      if (!Array.isArray(list) || list.some((n) => typeof n !== "string")) {
        problems.push(`${where}: ${field} must be a list of clip names`);
      }
    }
  }

  return problems;
}

const MAX_LEVEL = 100;

// A rate is in 256ths (spec 14, section 4). The build is stricter than the
// engine on purpose: 0 would be a zone where nothing ever appears and 256 one
// where an encounter is certain, and both are far more likely to be a mistake
// than an intention. The engine still tolerates them, because refusing at
// runtime would be refusing in front of a player.
const MIN_RATE = 1;
const MAX_RATE = 255;

// Encounter tables have no oracle (spec 02), so shape and cross-reference are
// the whole of the automatic guard they get.
function validateEncounters(tables, knownSpecies) {
  const problems = [];

  for (const table of tables) {
    const where = `encounter table "${table.id}"`;

    if (!Number.isInteger(table.rate) || table.rate < MIN_RATE || table.rate > MAX_RATE) {
      problems.push(`${where}: rate must be ${MIN_RATE}-${MAX_RATE} (256ths)`);
    }

    // An empty table is a zone that can fire and then has nothing to show. The
    // engine asserts on it, but by then a player is standing in the grass.
    if (!Array.isArray(table.slots) || table.slots.length === 0) {
      problems.push(`${where}: needs at least one slot`);
      continue;
    }

    let total = 0;
    for (const slot of table.slots) {
      const which = `${where}, slot "${slot.species}"`;

      if (!knownSpecies.has(slot.species)) {
        problems.push(`${which}: unknown species`);
      }
      if (!Number.isInteger(slot.weight) || slot.weight < 1) {
        problems.push(`${which}: weight must be a positive integer`);
      } else {
        total += slot.weight;
      }

      const from = slot.levels?.min;
      const to = slot.levels?.max;
      if (!Number.isInteger(from) || !Number.isInteger(to)) {
        problems.push(`${which}: levels need an integer min and max`);
      } else if (from < 1 || to > MAX_LEVEL) {
        problems.push(`${which}: levels must be 1-${MAX_LEVEL}`);
      } else if (from > to) {
        problems.push(`${which}: levels run from ${from} down to ${to}`);
      }
    }

    // Nothing downstream can draw from a table with no weight, and the check
    // above passes when every slot is individually fine and the array is empty
    // of valid ones.
    if (total < 1) problems.push(`${where}: no slot carries any weight`);
  }

  return problems;
}

// The same structural claims the seeding tool checked, re-checked here so an
// edit to the committed table is caught by the build rather than by a player
// whose creature stopped levelling. Progression has no oracle (spec 02), so
// these are the only automatic guard these numbers get.
function validateCurves(data, knownRates) {
  const problems = [];

  for (const rate of knownRates) {
    if (!(rate in data.curves)) problems.push(`growth curves: "${rate}" is missing`);
  }

  for (const [name, totals] of Object.entries(data.curves)) {
    const where = `growth curve "${name}"`;

    if (!knownRates.has(name)) problems.push(`${where}: not a declared growth rate`);
    if (totals.length !== MAX_LEVEL) {
      problems.push(`${where}: ${totals.length} levels, expected ${MAX_LEVEL}`);
      continue;
    }
    if (totals[0] !== 0) problems.push(`${where}: level 1 is not zero`);

    for (let index = 1; index < totals.length; index++) {
      if (!Number.isInteger(totals[index])) {
        problems.push(`${where}: level ${index + 1} is not an integer`);
      }
      if (totals[index] <= totals[index - 1]) {
        problems.push(`${where}: level ${index + 1} does not exceed the one before it`);
      }
    }
  }

  return problems;
}

const STATS = ["hp", "atk", "def", "spa", "spd", "spe"];
const GROWTH_RATES = new Set(["erratic", "fast", "medium_fast", "medium_slow", "slow", "fluctuating"]);
const EVOLUTION_TRIGGERS = new Set(["level"]);
const GENDERLESS = "genderless";

// Bounds come from spec 09 section 4. The last group is named and checked here
// but given meaning by specs 10 and 11 — a field whose range is declared is a
// field the build can already defend, even before a formula reads it.
function validateSpecies(species, knownTypes, knownMoves) {
  const problems = [];
  const known = new Set(species.map((entry) => entry.id));

  for (const entry of species) {
    const where = `species "${entry.id}"`;

    if (!Array.isArray(entry.types) || entry.types.length < 1 || entry.types.length > 2) {
      problems.push(`${where}: needs one or two types`);
    }
    for (const type of entry.types ?? []) {
      if (!knownTypes.has(type)) problems.push(`${where}: unknown type "${type}"`);
    }
    if (new Set(entry.types ?? []).size !== (entry.types ?? []).length) {
      problems.push(`${where}: the same type twice`);
    }

    for (const stat of STATS) {
      const value = entry.base_stats?.[stat];
      if (!Number.isInteger(value) || value < 1 || value > 255) {
        problems.push(`${where}: base_stats.${stat} must be 1-255`);
      }
      const yielded = entry.ev_yield?.[stat];
      if (!Number.isInteger(yielded) || yielded < 0) {
        problems.push(`${where}: ev_yield.${stat} must be a non-negative integer`);
      }
    }

    const yieldTotal = STATS.reduce((sum, stat) => sum + (entry.ev_yield?.[stat] ?? 0), 0);
    if (yieldTotal > 3) problems.push(`${where}: ev_yield totals ${yieldTotal}, more than 3`);

    // Ascending levels, because a learnset read in file order has to BE in
    // order — sorting it here would hide an authoring mistake rather than
    // report it.
    let previous = 0;
    for (const learned of entry.learnset?.level_up ?? []) {
      if (!knownMoves.has(learned.move)) {
        problems.push(`${where}: learns unknown move "${learned.move}"`);
      }
      if (learned.level < 1 || learned.level > 100) {
        problems.push(`${where}: learns "${learned.move}" at level ${learned.level}`);
      }
      if (learned.level < previous) {
        problems.push(`${where}: learnset is out of order at "${learned.move}"`);
      }
      previous = learned.level;
    }

    for (const evolution of entry.evolutions ?? []) {
      if (!known.has(evolution.into)) {
        problems.push(`${where}: evolves into unknown species "${evolution.into}"`);
      }
      if (evolution.into === entry.id) problems.push(`${where}: evolves into itself`);
      if (!EVOLUTION_TRIGGERS.has(evolution.trigger)) {
        problems.push(`${where}: unknown evolution trigger "${evolution.trigger}"`);
      }
      if (evolution.trigger === "level" && !Number.isInteger(evolution.level)) {
        problems.push(`${where}: a level evolution needs a level`);
      }
    }

    if (!GROWTH_RATES.has(entry.growth_rate)) {
      problems.push(`${where}: unknown growth_rate "${entry.growth_rate}"`);
    }
    if (!Number.isInteger(entry.base_experience) || entry.base_experience < 1) {
      problems.push(`${where}: base_experience must be a positive integer`);
    }
    if (!Number.isInteger(entry.catch_rate) || entry.catch_rate < 3 || entry.catch_rate > 255) {
      problems.push(`${where}: catch_rate must be 3-255`);
    }

    const ratio = entry.gender_ratio;
    if (ratio !== GENDERLESS && (!Number.isInteger(ratio) || ratio < 0 || ratio > 8)) {
      problems.push(`${where}: gender_ratio must be 0-8 eighths or "${GENDERLESS}"`);
    }
  }

  problems.push(...evolutionCycles(species));
  return problems;
}

// A cycle would be an evolution chain with no end. Nothing downstream would
// crash on it; it would simply never terminate, somewhere far from here.
function evolutionCycles(species) {
  const graph = new Map(species.map((e) => [e.id, (e.evolutions ?? []).map((v) => v.into)]));
  const problems = [];
  const state = new Map(); // unvisited | visiting | done

  const walk = (id, path) => {
    if (state.get(id) === "done") return;
    if (state.get(id) === "visiting") {
      problems.push(`evolution cycle: ${[...path, id].join(" -> ")}`);
      return;
    }
    state.set(id, "visiting");
    for (const next of graph.get(id) ?? []) {
      if (graph.has(next)) walk(next, [...path, id]);
    }
    state.set(id, "done");
  };

  for (const entry of species) walk(entry.id, []);
  return problems;
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
  const curves = loadCurves();
  const moves = loadMoves();
  const species = loadSpecies();
  const items = loadItems();
  const encounters = loadEncounters();
  const presentation = loadPresentation();
  const knownTypes = new Set(chart.types);
  const knownMoves = new Set(moves.map((move) => move.id));
  const knownSpecies = new Set(species.map((entry) => entry.id));

  report([
    ...validateChart(chart),
    ...validateNatures(natures),
    ...validateMoves(moves, knownTypes),
    ...validateSpecies(species, knownTypes, knownMoves),
    ...validateCurves(curves, GROWTH_RATES),
    ...validateItems(items),
    ...validateEncounters(encounters, knownSpecies),
    ...validatePresentation(presentation, knownSpecies),
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

  const speciesDir = writeEntities("species", species);
  console.log(`species:    ${species.length} entries -> ${speciesDir}/`);

  const itemsDir = writeEntities("items", items);
  console.log(`items:      ${items.length} entries -> ${itemsDir}/`);

  const encountersDir = writeEntities("encounters", encounters);
  const slots = encounters.reduce((n, table) => n + table.slots.length, 0);
  console.log(`encounters: ${encounters.length} tables, ${slots} slots -> ${encountersDir}/`);

  const presentationDir = writeEntities("presentation", presentation);
  writeFileSync(
    join(presentationDir, "vocabulary.json"),
    JSON.stringify({ version: SCHEMA_VERSION, slots: SLOTS }, null, 2) + "\n",
  );
  console.log(`presentation: ${presentation.length} manifests, ${EVERY_SLOT.size} slots -> ${presentationDir}/`);

  const curvesPath = join(OUT_DIR, "growth-curves.json");
  writeFileSync(curvesPath, JSON.stringify(curves, null, 2) + "\n");
  console.log(`curves:     ${Object.keys(curves.curves).length} curves -> ${curvesPath}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
