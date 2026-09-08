#!/usr/bin/env node
// Generates damage procedure vectors from the oracle.
//
// Substituting the randomizer is the same mechanism decision 0009 describes:
// the two engines share answers, not random numbers. Forcing each of the
// sixteen rolls yields the full spread without touching a seed.
//
// Fixtures record NUMBERS AND VOLTARI IDS ONLY. Oracle species and move names
// live here, on the tooling side of the clean-room boundary, and never reach
// tests/fixtures/. See docs/specs/02-fidelity-contract.md, section 3.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Battle, Teams } from "@pkmn/sim";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "..", "..", "tests", "fixtures", "oracle", "procedure", "damage");

const ROLLS = 16; // Gen 4 randomizer spans 85..100 inclusive.
const MAX_IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };
const ZERO_EVS = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };

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

// Runs one battle with the damage roll forced to `roll` percent.
function damageAtRoll(scenario, roll) {
  const battle = new Battle({
    formatid: "gen4customgame",
    seed: [1, 2, 3, 4],
    p1: { name: "P1", team: Teams.pack([set(scenario.attacker)]) },
    p2: { name: "P2", team: Teams.pack([set(scenario.defender)]) },
  });

  // The scripted decision policy of spec 02, answered PER DECISION KIND.
  // A single blanket answer to every chance is wrong: `randomChance` also backs
  // the accuracy roll, so answering it "no" everywhere makes every move miss.
  // This is the empirical case for decision 0010's semantic interface.
  battle.randomizer = (baseDamage) => Math.floor((baseDamage * roll) / 100); // damage roll: forced
  battle.randomChance = () => false; // critical, secondary: never
  battle.actions.hitStepAccuracy = (targets) => targets.map(() => true); // accuracy: always hit

  const target = battle.sides[1].active[0];
  const before = target.hp;
  battle.makeChoices("move 1", "move 1");
  const damage = before - target.hp;

  // Damage is measured as HP lost, so a fainting target silently truncates it.
  // A capped vector looks plausible and is wrong, so it must never be emitted.
  if (target.hp === 0) {
    throw new Error(
      `${scenario.id}: target fainted at roll ${roll}; damage would be capped at ${before}. ` +
        `Pick a bulkier defender or a weaker move.`,
    );
  }

  return { damage, target, attacker: battle.sides[0].active[0] };
}

// Anonymised description of the scenario: numbers only, no oracle identifiers.
function describe(attacker, target, scenario) {
  return {
    level: attacker.level,
    move: {
      power: scenario.movePower,
      type: scenario.moveType,
      category: scenario.moveCategory,
    },
    attacker: {
      attack: attacker.storedStats.atk,
      special_attack: attacker.storedStats.spa,
      types: attacker.types.map((t) => t.toLowerCase()),
    },
    defender: {
      hp: target.maxhp,
      defense: target.storedStats.def,
      special_defense: target.storedStats.spd,
      types: target.types.map((t) => t.toLowerCase()),
    },
    context: { critical: false, weather: null, screens: [] },
  };
}

function generate(scenario) {
  const rolls = [];
  let described = null;

  for (let i = 0; i < ROLLS; i++) {
    const { damage, target, attacker } = damageAtRoll(scenario, 85 + i);
    rolls.push(damage);
    if (described === null) described = describe(attacker, target, scenario);
  }

  return { id: scenario.id, kind: "damage", input: described, expected: { rolls } };
}

const SCENARIOS = [
  {
    id: "damage/0001",
    attacker: { species: "Machamp", moves: ["Tackle"], ability: "noguard" },
    defender: { species: "Blissey", moves: ["Splash"] },
    movePower: 35,
    moveType: "normal",
    moveCategory: "physical",
  },
  {
    id: "damage/0002",
    attacker: { species: "Alakazam", moves: ["Psychic"], ability: "noability" },
    defender: { species: "Snorlax", moves: ["Splash"] },
    movePower: 90,
    moveType: "psychic",
    moveCategory: "special",
  },
];

const vectors = SCENARIOS.map(generate);
mkdirSync(OUT_DIR, { recursive: true });
const path = join(OUT_DIR, "basic.json");
writeFileSync(path, JSON.stringify({ vectors }, null, 2) + "\n");

for (const v of vectors) {
  console.log(`${v.id}  rolls ${v.expected.rolls[0]}..${v.expected.rolls[ROLLS - 1]}`);
}
console.log(`\nwrote ${vectors.length} vector(s) to ${path}`);
