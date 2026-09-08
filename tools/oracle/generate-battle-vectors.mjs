#!/usr/bin/env node
// Battle differential vectors: scripted battles replayed on the oracle, with
// their logs projected into a shared vocabulary (decision 0009).
//
// Procedure vectors assert formulas. This asserts ORDER — the actual risk of
// the project, and something no isolated formula test can reach.
//
// Both engines are driven by the same decision policy, answered per kind. They
// share answers, never random numbers, because Voltari has its own generator.
//
// Fixtures carry numbers and Voltari-side vocabulary only. Oracle names stay
// here, on the tooling side of the clean-room boundary.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Battle, Dex, Teams } from "@pkmn/sim";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT_DIR = join(REPO, "tests", "fixtures", "oracle", "battle");

const GEN4 = Dex.forGen(4);

// The one crossing point between the two vocabularies (spec 02, section 3).
// Oracle identifiers stay on this side; the fixture carries only Voltari ids.
const STATUS_TO_EFFECT = { brn: "burn" };
const SIDE_CONDITION_TO_EFFECT = { reflect: "reflect" };
const STATS = ["hp", "atk", "def", "spa", "spd", "spe"];
const ZERO_EVS = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const MAX_IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };

// Protocol messages that exist on one side only. Each needs a reason: an event
// silently dropped from the projection is a hole in the differential
// (spec 02, section 6).
const IGNORED = {
  "t:": "wall-clock timestamp, not a game event",
  gametype: "battle setup, not a turn event",
  player: "battle setup",
  teamsize: "battle setup",
  gen: "battle setup",
  tier: "battle setup",
  rule: "battle setup",
  start: "battle setup",
  turn: "Voltari emits turn_start with a number; compared separately",
  upkeep: "end-of-turn marker with no Voltari counterpart",
  split: "visibility marker; the private line that follows is the one read",
  "-crit": "Voltari records criticals on the damage event, not as a message",
  "-supereffective": "folded into the effectiveness event",
  "-resisted": "folded into the effectiveness event",
  "-immune": "folded into the effectiveness event",
  "-damage": "handled explicitly",
  "-heal": "handled explicitly",
  "-fail": "Voltari has no failure taxonomy for these yet",
  "-notarget": "Voltari reports NO_TARGET on move_failed",
  "-miss": "Voltari reports MISSED on move_failed",
  "-message": "flavour text",
  "-anim": "presentation",
  "-hint": "presentation",
  "-activate": "effect system, not yet modelled",
  "-start": "effect system, not yet modelled",
  "-end": "effect system, not yet modelled",
  "-status": "effect system, not yet modelled",
  "-boost": "effect system, not yet modelled",
  "-unboost": "effect system, not yet modelled",
  "-weather": "effect system, not yet modelled",
  "-sidestart": "effect system, not yet modelled",
  "-sideend": "effect system, not yet modelled",
  "-ability": "effect system, not yet modelled",
  "-item": "effect system, not yet modelled",
  "-enditem": "effect system, not yet modelled",
  debug: "oracle diagnostic output, not a game event",
  win: "battle outcome, compared through the final state",
  "": "blank separator",
};

function set(overrides) {
  return {
    name: overrides.species,
    item: "",
    ability: "noability",
    moves: ["tackle"],
    nature: "Hardy",
    evs: ZERO_EVS,
    ivs: MAX_IVS,
    level: 50,
    gender: "N",
    happiness: 255,
    shiny: false,
    ...overrides,
  };
}

// --- the shared vocabulary --------------------------------------------------

function slotOf(tag) {
  // "p1a: Machamp" -> {side: 0, slot: 0}
  const match = /^p(\d)([a-c])/.exec(tag);
  if (match === null) return null;
  return { side: Number(match[1]) - 1, slot: match[2].charCodeAt(0) - "a".charCodeAt(0) };
}

function project(lines, movesByPokemon) {
  const events = [];
  const unknown = new Set();
  let skipNext = false;

  for (const line of lines) {
    if (!line.startsWith("|")) continue;
    const parts = line.slice(1).split("|");
    const tag = parts[0];

    // `|split|pN` is followed by the private line then the public one. The
    // private line carries exact HP, so read it and drop its public twin.
    if (tag === "split") {
      skipNext = false;
      continue;
    }
    if (skipNext) {
      skipNext = false;
      continue;
    }

    switch (tag) {
      case "move": {
        const actor = slotOf(parts[1]);
        const known = movesByPokemon.get(parts[1].split(": ")[1]) ?? [];
        events.push({
          kind: "move",
          side: actor.side,
          slot: actor.slot,
          move_index: known.indexOf(Dex.moves.get(parts[2]).id),
        });
        break;
      }
      case "-damage":
      case "-heal": {
        const target = slotOf(parts[1]);
        const [current] = parts[2].split(" ")[0].split("/");
        events.push({
          kind: tag === "-damage" ? "damage" : "heal",
          side: target.side,
          slot: target.slot,
          hp_after: current === "0" ? 0 : Number(current),
        });
        skipNext = true; // the public twin
        break;
      }
      case "-supereffective":
      case "-resisted": {
        const target = slotOf(parts[1]);
        events.push({
          kind: "effectiveness",
          side: target.side,
          slot: target.slot,
          level: tag === "-supereffective" ? "super" : "resisted",
        });
        break;
      }
      case "faint": {
        const target = slotOf(parts[1]);
        events.push({ kind: "faint", side: target.side, slot: target.slot });
        skipNext = false;
        break;
      }
      case "switch": {
        const target = slotOf(parts[1]);
        events.push({ kind: "switch", side: target.side, slot: target.slot });
        skipNext = true;
        break;
      }
      default:
        if (!(tag in IGNORED)) unknown.add(tag);
    }
  }

  return { events, unknown: [...unknown] };
}

// --- running a scenario -----------------------------------------------------

// The identifier is positional, never the oracle's: a fixture that names an
// oracle entity is a defect in the generator (spec 02, section 3).
function describeMove(id, prefix, index) {
  const move = GEN4.moves.get(id);
  return {
    // Unique per creature, not merely per position: the engine's move registry
    // is shared across the battle, so `move_0` twice would collide.
    id: `${prefix}_m${index}`,
    type: move.type.toLowerCase(),
    category: move.category.toLowerCase(),
    power: move.basePower,
    accuracy: move.accuracy === true ? -1 : move.accuracy,
    priority: move.priority,
    pp: Math.floor((move.pp * 8) / 5),
  };
}

function describeCreature(pokemon, moveIds, prefix) {
  const species = GEN4.species.get(pokemon.species.name);
  const base = {};
  for (const stat of STATS) base[stat] = species.baseStats[stat];
  return {
    level: pokemon.level,
    types: pokemon.types.map((t) => t.toLowerCase()),
    base: STATS.map((s) => base[s]),
    ivs: STATS.map((s) => MAX_IVS[s]),
    evs: STATS.map((s) => ZERO_EVS[s]),
    stats: STATS.map((s) => (s === "hp" ? pokemon.maxhp : pokemon.storedStats[s])),
    moves: moveIds.map((id, index) => describeMove(id, prefix, index)),
  };
}

function run(scenario) {
  const battle = new Battle({
    formatid: "gen4customgame",
    seed: [1, 2, 3, 4],
    p1: { name: "P1", team: Teams.pack(scenario.sides[0].map(set)) },
    p2: { name: "P2", team: Teams.pack(scenario.sides[1].map(set)) },
  });

  // The decision policy, answered per kind (decision 0010).
  const policy = scenario.policy;
  battle.randomizer = (baseDamage) => Math.floor((baseDamage * (85 + policy.damage_roll_index)) / 100);
  battle.randomChance = () => policy.critical === "always";
  battle.actions.hitStepAccuracy = (targets) => targets.map(() => policy.accuracy === "always");

  // Speed ties are resolved by shuffling the tied slice. Intercepting it makes
  // the tie a DECLARED decision on both sides rather than a draw — which is the
  // whole point of the policy: shared answers, not shared random numbers.
  battle.prng.shuffle = (list, start = 0, end = list.length) => {
    const slice = list.slice(start, end);

    // Normalise to the engine's canonical order first — side, then position —
    // so "earlier" means the same thing on both sides of the differential.
    const sideOf = (action) => action?.pokemon?.side?.n ?? 0;
    const slotOf = (action) => action?.pokemon?.position ?? 0;
    slice.sort((a, b) => sideOf(a) - sideOf(b) || slotOf(a) - slotOf(b));

    // Then mirror the engine's adjacent-pair walk rather than reversing the
    // slice. The two agree on a pair and diverge on three or more, which a
    // doubles vector would reach.
    if (policy.speed_tie_winner === "later") {
      for (let i = 1; i < slice.length; i++) {
        [slice[i - 1], slice[i]] = [slice[i], slice[i - 1]];
      }
    }

    for (let i = 0; i < slice.length; i++) list[start + i] = slice[i];
  };

  const movesByPokemon = new Map();
  for (const side of scenario.sides) {
    for (const member of side) {
      movesByPokemon.set(member.species, member.moves.map((m) => Dex.moves.get(m).id));
    }
  }

  const parties = [[], []];
  for (const side of [0, 1]) {
    for (let index = 0; index < battle.sides[side].pokemon.length; index++) {
      const pokemon = battle.sides[side].pokemon[index];
      parties[side].push(
        describeCreature(pokemon, movesByPokemon.get(pokemon.species.name), `s${side}p${index}`),
      );
    }
  }

  // Conditions set up before the script runs, recorded in Voltari vocabulary so
  // the engine can reproduce the same starting position.
  const conditions = [];
  for (const [index, side] of (scenario.conditions ?? []).entries()) {
    if (side?.status) {
      battle.sides[index].active[0].setStatus(side.status);
      conditions.push({ effect: STATUS_TO_EFFECT[side.status], side: index, slot: 0 });
    }
    for (const condition of side?.side_conditions ?? []) {
      battle.sides[index].addSideCondition(condition, battle.sides[index].active[0]);
      conditions.push({ effect: SIDE_CONDITION_TO_EFFECT[condition], side: index, slot: 0 });
    }
  }

  const startIndex = battle.log.length;
  for (const turn of scenario.script) {
    if (battle.ended) break;
    battle.makeChoices(...turn);
  }

  const projected = project(battle.log.slice(startIndex), movesByPokemon);
  if (projected.unknown.length > 0) {
    throw new Error(
      `${scenario.id}: unmapped protocol messages ${projected.unknown.join(", ")}. ` +
        `Add them to the projection or to IGNORED with a reason.`,
    );
  }

  return {
    id: scenario.id,
    policy: scenario.policy,
    conditions,
    parties,
    script: scenario.script_commands,
    expected: projected.events,
  };
}

// --- scenarios --------------------------------------------------------------

const POLICY = {
  damage_roll_index: 15,
  accuracy: "always",
  critical: "never",
  secondary: "never",
  speed_tie_winner: "earlier",
};

const SCENARIOS = [
  {
    id: "battle/0005-burn",
    policy: POLICY,
    sides: [
      [{ species: "Machamp", moves: ["Tackle"] }],
      [{ species: "Blissey", moves: ["Tackle"] }],
    ],
    conditions: [{ status: "brn" }, {}],
    script: [["move 1", "move 1"], ["move 1", "move 1"]],
    script_commands: [
      [{ kind: "move", index: 0 }, { kind: "move", index: 0 }],
      [{ kind: "move", index: 0 }, { kind: "move", index: 0 }],
    ],
  },
  {
    id: "battle/0006-screen",
    policy: POLICY,
    sides: [
      [{ species: "Machamp", moves: ["Tackle"] }],
      [{ species: "Blissey", moves: ["Tackle"] }],
    ],
    conditions: [{}, { side_conditions: ["reflect"] }],
    // Long enough for the screen to expire and damage to jump back up.
    script: Array.from({ length: 6 }, () => ["move 1", "move 1"]),
    script_commands: Array.from({ length: 6 }, () => [
      { kind: "move", index: 0 },
      { kind: "move", index: 0 },
    ]),
  },
  {
    id: "battle/0001-trade",
    policy: POLICY,
    sides: [
      [{ species: "Machamp", moves: ["Tackle"] }],
      [{ species: "Blissey", moves: ["Tackle"] }],
    ],
    script: [["move 1", "move 1"], ["move 1", "move 1"]],
    script_commands: [
      [{ kind: "move", index: 0 }, { kind: "move", index: 0 }],
      [{ kind: "move", index: 0 }, { kind: "move", index: 0 }],
    ],
  },
  {
    id: "battle/0002-priority",
    policy: POLICY,
    sides: [
      [{ species: "Slowpoke", moves: ["Quick Attack", "Tackle"] }],
      [{ species: "Jolteon", moves: ["Tackle"] }],
    ],
    script: [["move 1", "move 1"]],
    script_commands: [[{ kind: "move", index: 0 }, { kind: "move", index: 0 }]],
  },
  {
    id: "battle/0003-effectiveness",
    policy: POLICY,
    sides: [
      [{ species: "Vaporeon", moves: ["Surf"] }],
      [{ species: "Rhyperior", moves: ["Tackle"] }],
    ],
    script: [["move 1", "move 1"]],
    script_commands: [[{ kind: "move", index: 0 }, { kind: "move", index: 0 }]],
  },
  {
    id: "battle/0004-switch",
    policy: POLICY,
    sides: [
      [{ species: "Machamp", moves: ["Tackle"] }, { species: "Snorlax", moves: ["Tackle"] }],
      [{ species: "Blissey", moves: ["Tackle"] }],
    ],
    script: [["switch 2", "move 1"], ["move 1", "move 1"]],
    script_commands: [
      [{ kind: "switch", party: 1 }, { kind: "move", index: 0 }],
      [{ kind: "move", index: 0 }, { kind: "move", index: 0 }],
    ],
  },
];

const vectors = SCENARIOS.map(run);

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(
  join(OUT_DIR, "scripted.json"),
  JSON.stringify({ oracle: "@pkmn/sim 0.10.11 gen4", ignored: IGNORED, vectors }, null, 2) + "\n",
);

for (const vector of vectors) {
  const kinds = vector.expected.map((e) => e.kind).join(" ");
  console.log(`${vector.id.padEnd(28)} ${vector.expected.length} events: ${kinds}`);
}
console.log(`\nwrote ${vectors.length} battle vector(s)`);
