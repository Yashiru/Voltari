#!/usr/bin/env node
// Oracle probe: drives a controlled gen4 battle and prints the raw protocol log.
//
// Development tooling. Read as behavioural documentation only — no oracle code
// is copied into the engine. See docs/specs/02-fidelity-contract.md.

import { Battle, Teams } from "@pkmn/sim";

const ZERO_EVS = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const MAX_IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };

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

function runBattle(p1set, p2set, choices) {
  const battle = new Battle({
    formatid: "gen4customgame",
    seed: [1, 2, 3, 4],
    p1: { name: "P1", team: Teams.pack([set(p1set)]) },
    p2: { name: "P2", team: Teams.pack([set(p2set)]) },
  });
  battle.makeChoices(...choices);
  return battle;
}

const battle = runBattle(
  { species: "Machamp", moves: ["Payback"], ability: "noguard" },
  { species: "Blissey", moves: ["Splash"] },
  ["move 1", "move 1"],
);

console.log("--- protocol log ---");
console.log(battle.log.join("\n"));
console.log("\n--- p2 active ---");
const target = battle.sides[1].active[0];
console.log(`hp=${target.hp}/${target.maxhp}`);
