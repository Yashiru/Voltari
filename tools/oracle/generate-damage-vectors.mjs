#!/usr/bin/env node
// Generates damage procedure vectors from the oracle, one scenario per pipeline
// stage, and verifies that every stage of the engine enum is covered.
//
// The decision policy is answered PER KIND (decision 0010), never by a single
// blanket answer: a global "no" also answers the accuracy roll and makes every
// move miss.
//
// Fixtures carry NUMBERS AND VOLTARI IDS ONLY. Oracle species and move names
// live here, on the tooling side of the clean-room boundary.
// See docs/specs/02-fidelity-contract.md, section 3.

import { writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Battle, Dex, Teams } from "@pkmn/sim";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT_DIR = join(REPO, "tests", "fixtures", "oracle", "procedure", "damage");
const STAGE_ENUM = join(REPO, "addons", "voltari", "core", "formulas", "damage_stage.gd");

const TOLERANCE = 0.1;
const GEN4 = Dex.forGen(4);

// Showdown's damageTaken encoding: 0 neutral, 1 super effective, 2 resisted,
// 3 immune. The exponent is what stage 10 consumes; the chart lookup that
// produces it is a separate procedure with its own vectors (spec 09).
function effectivenessExponent(moveType, defenderTypes) {
  let exponent = 0;
  for (const type of defenderTypes) {
    const code = GEN4.types.get(type).damageTaken[moveType];
    if (code === 1) exponent += 1;
    else if (code === 2) exponent -= 1;
    else if (code === 3) return null; // immune: damage never reaches the pipeline
  }
  return exponent;
}

const ROLLS = 16; // The Gen 4 randomizer spans 85..100 inclusive.
const MAX_IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };
const ZERO_EVS = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };

// Stages that no black-box scenario can isolate: they are present in every
// vector rather than switchable. Declared rather than silently missing.
const STRUCTURAL_STAGES = new Set([
  "PLUS_TWO",
  "MODIFIER_PHASE_2",
  "FINAL_MODIFIER",
  "RANDOM_ROLL",
]);

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

function teamOf(sets) {
  return Teams.pack(sets.map(set));
}

// One battle, with the damage roll forced to `roll` percent.
function runAtRoll(scenario, roll) {
  const doubles = scenario.gametype === "doubles";
  const battle = new Battle({
    formatid: doubles ? "gen4doublescustomgame" : "gen4customgame",
    seed: [1, 2, 3, 4],
    p1: { name: "P1", team: teamOf(scenario.attackers) },
    p2: { name: "P2", team: teamOf(scenario.defenders) },
  });

  // Scripted decision policy, answered per decision kind.
  battle.randomizer = (baseDamage) => Math.floor((baseDamage * roll) / 100);
  battle.randomChance = () => scenario.critical === true;
  battle.actions.hitStepAccuracy = (targets) => targets.map(() => true);

  const attacker = battle.sides[0].active[0];
  const target = battle.sides[1].active[0];

  // Conditions need a source, so each is attributed to the side that carries it.
  if (scenario.attackerStatus) attacker.setStatus(scenario.attackerStatus);
  if (scenario.weather) battle.field.setWeather(scenario.weather, target);
  for (const condition of scenario.defenderSideConditions ?? []) {
    battle.sides[1].addSideCondition(condition, target);
  }

  const before = target.hp;
  battle.makeChoices(...scenario.choices);
  const damage = before - target.hp;

  // Damage is read as HP lost, so a fainting target silently truncates it.
  // A capped vector looks plausible and is wrong, so it must never be emitted.
  if (target.hp === 0) {
    throw new Error(
      `${scenario.id}: target fainted at roll ${roll}, damage capped at ${before}. ` +
        `Use a bulkier defender or a weaker move.`,
    );
  }

  return { damage, attacker, target, log: battle.log };
}

// Anonymised: numbers and Voltari-side vocabulary only.
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
      status: scenario.attackerStatus ?? null,
    },
    defender: {
      hp: target.maxhp,
      defense: target.storedStats.def,
      special_defense: target.storedStats.spd,
      types: target.types.map((t) => t.toLowerCase()),
    },
    context: {
      stab: attacker.types.some((t) => t.toLowerCase() === scenario.moveType),
      type_effectiveness_exponent: effectivenessExponent(
        scenario.moveType[0].toUpperCase() + scenario.moveType.slice(1),
        target.types,
      ),
      critical: scenario.critical === true,
      weather: scenario.weatherId ?? null,
      weather_modifier: scenario.weatherModifier ?? [1, 1],
      screens: scenario.screens ?? [],
      spread: scenario.gametype === "doubles",
    },
  };
}

function generate(scenario) {
  const rolls = [];
  let described = null;
  let sawCrit = false;

  for (let i = 0; i < ROLLS; i++) {
    const { damage, attacker, target, log } = runAtRoll(scenario, 85 + i);
    rolls.push(damage);
    if (described === null) described = describe(attacker, target, scenario);
    if (log.some((line) => line.startsWith("|-crit|"))) sawCrit = true;
  }

  // The scenario claims a context; the oracle must actually have applied it.
  if (scenario.critical === true && !sawCrit) {
    throw new Error(`${scenario.id}: claims a critical hit, oracle never reported one.`);
  }
  if (scenario.critical !== true && sawCrit) {
    throw new Error(`${scenario.id}: oracle reported a critical hit that was not requested.`);
  }

  return {
    id: scenario.id,
    kind: "damage",
    stages: scenario.stages,
    control: scenario.control ?? null,
    expected_ratio: scenario.expected_ratio ?? null,
    input: described,
    expected: { rolls },
  };
}

// ---------------------------------------------------------------------------

const SINGLE = ["move 1", "move 1"];
const BULKY = { species: "Blissey", moves: ["Splash"] };
// Water resists neither Normal nor Fighting, so a STAB pair against it varies
// exactly one factor. Blissey would not: Fighting is super effective on Normal,
// which silently folds effectiveness into the ratio.
const NEUTRAL_TO_NORMAL_AND_FIGHTING = { species: "Vaporeon", moves: ["Splash"] };

const SCENARIOS = [
  {
    id: "damage/baseline/0001",
    stages: [],
    attackers: [{ species: "Machamp", moves: ["Tackle"] }],
    defenders: [BULKY],
    movePower: 35,
    moveType: "normal",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/burn/0001",
    control: "damage/baseline/0001",
    expected_ratio: 0.5,
    stages: ["BURN"],
    attackers: [{ species: "Machamp", moves: ["Tackle"] }],
    defenders: [BULKY],
    attackerStatus: "brn",
    movePower: 35,
    moveType: "normal",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/screen/0001",
    control: "damage/baseline/0001",
    expected_ratio: 0.5,
    stages: ["MODIFIER_PHASE_1"],
    attackers: [{ species: "Machamp", moves: ["Tackle"] }],
    defenders: [BULKY],
    defenderSideConditions: ["reflect"],
    screens: ["reflect"],
    movePower: 35,
    moveType: "normal",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/weather/control",
    stages: [],
    attackers: [{ species: "Vaporeon", moves: ["Water Gun"] }],
    defenders: [BULKY],
    movePower: 40,
    moveType: "water",
    moveCategory: "special",
    choices: SINGLE,
  },
  {
    id: "damage/weather/0001",
    control: "damage/weather/control",
    expected_ratio: 1.5,
    stages: ["WEATHER"],
    attackers: [{ species: "Vaporeon", moves: ["Water Gun"] }],
    defenders: [BULKY],
    weather: "raindance",
    weatherId: "rain",
    weatherModifier: [3, 2],
    movePower: 40,
    moveType: "water",
    moveCategory: "special",
    choices: SINGLE,
  },
  {
    id: "damage/critical/0001",
    control: "damage/baseline/0001",
    expected_ratio: 2.0,
    stages: ["CRITICAL"],
    attackers: [{ species: "Machamp", moves: ["Tackle"] }],
    defenders: [BULKY],
    critical: true,
    movePower: 35,
    moveType: "normal",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/stab/control",
    stages: [],
    attackers: [{ species: "Machamp", moves: ["Pound"] }],
    defenders: [NEUTRAL_TO_NORMAL_AND_FIGHTING],
    movePower: 40,
    moveType: "normal",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/stab/0001",
    control: "damage/stab/control",
    expected_ratio: 1.5,
    stages: ["STAB"],
    attackers: [{ species: "Machamp", moves: ["Rock Smash"] }],
    defenders: [NEUTRAL_TO_NORMAL_AND_FIGHTING],
    movePower: 40,
    moveType: "fighting",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/effectiveness/0001",
    stages: ["TYPE_EFFECTIVENESS"],
    attackers: [{ species: "Alakazam", moves: ["Water Gun"] }],
    defenders: [{ species: "Rhyperior", moves: ["Splash"] }],
    movePower: 40,
    moveType: "water",
    moveCategory: "special",
    choices: SINGLE,
  },
  {
    id: "damage/effectiveness/0002",
    stages: ["TYPE_EFFECTIVENESS"],
    attackers: [{ species: "Alakazam", moves: ["Water Gun"] }],
    defenders: [{ species: "Vaporeon", moves: ["Splash"] }],
    movePower: 40,
    moveType: "water",
    moveCategory: "special",
    choices: SINGLE,
  },
  {
    id: "damage/minimum/0001",
    stages: ["FLOOR_MINIMUM"],
    attackers: [{ species: "Magikarp", moves: ["Tackle"], level: 1 }],
    defenders: [{ species: "Shuckle", moves: ["Splash"] }],
    movePower: 35,
    moveType: "normal",
    moveCategory: "physical",
    choices: SINGLE,
  },
  {
    id: "damage/spread/control",
    stages: [],
    attackers: [{ species: "Vaporeon", moves: ["Surf"] }],
    defenders: [BULKY],
    movePower: 95,
    moveType: "water",
    moveCategory: "special",
    choices: SINGLE,
  },
  {
    id: "damage/spread/0001",
    control: "damage/spread/control",
    expected_ratio: 0.75,
    stages: ["SPREAD"],
    gametype: "doubles",
    attackers: [
      { species: "Vaporeon", moves: ["Surf"] },
      { species: "Ditto", moves: ["Splash"] },
    ],
    defenders: [BULKY, { species: "Snorlax", moves: ["Splash"] }],
    movePower: 95,
    moveType: "water",
    moveCategory: "special",
    choices: ["move 1, move 1", "move 1, move 1"],
  },
];

// ---------------------------------------------------------------------------

function enumStages() {
  const source = readFileSync(STAGE_ENUM, "utf8");
  const body = source.slice(source.indexOf("enum Stage {"));
  return [...body.matchAll(/^\t([A-Z][A-Z0-9_]*),/gm)].map((m) => m[1]);
}

const vectors = SCENARIOS.map(generate);

const covered = new Set(vectors.flatMap((v) => v.stages));
const missing = enumStages().filter((s) => !covered.has(s) && !STRUCTURAL_STAGES.has(s));

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(
  join(OUT_DIR, "stages.json"),
  JSON.stringify(
    { oracle: "@pkmn/sim 0.10.11 gen4", structural_stages: [...STRUCTURAL_STAGES], vectors },
    null,
    2,
  ) + "\n",
);

for (const v of vectors) {
  const tag = v.stages.length ? v.stages.join(",") : "—";
  console.log(
    `${v.id.padEnd(30)} ${String(v.expected.rolls[0]).padStart(4)}..${String(v.expected.rolls[ROLLS - 1]).padEnd(4)}  ${tag}`,
  );
}

const byId = new Map(vectors.map((v) => [v.id, v]));
for (const treated of vectors.filter((v) => v.control !== null)) {
  const control = byId.get(treated.control);
  const lo = treated.expected.rolls[0] / control.expected.rolls[0];
  const hi = treated.expected.rolls[ROLLS - 1] / control.expected.rolls[ROLLS - 1];
  const want = treated.expected_ratio;
  // Integer flooring at every stage keeps the ratio off the exact figure.
  const ok = Math.abs(lo - want) <= TOLERANCE && Math.abs(hi - want) <= TOLERANCE;
  console.log(
    `${treated.id.padEnd(26)} / ${control.id.padEnd(24)} ` +
      `${lo.toFixed(3)}..${hi.toFixed(3)}  want ~${want}  ${ok ? "ok" : "OFF"}`,
  );
  if (!ok) {
    console.error(
      `
${treated.id}: ratio is not ~${want}. ` +
        `The control probably varies more than one factor.`,
    );
    process.exitCode = 1;
  }
}

console.log(`\nstages covered by a dedicated scenario: ${[...covered].sort().join(", ")}`);
console.log(`structurally present in every vector: ${[...STRUCTURAL_STAGES].sort().join(", ")}`);

if (missing.length > 0) {
  console.error(`\nUNCOVERED STAGES: ${missing.join(", ")}`);
  process.exit(1);
}
console.log("\nevery pipeline stage is accounted for.");
