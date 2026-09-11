// Refuses to let third-party species assets enter the repository or a build.
//
//   node tools/species-guard/species-guard.mjs [--staged] [--quiet]
//
// The species are Pokemon GO models used to test gameplay until the real
// assets arrive. They are not ours, they are not licensed to us, and they must
// never be committed, pushed, or compiled into an export.
//
// Ignore rules alone do not achieve that. They do not apply to a file that is
// already tracked, `git add -f` walks straight past them, and they say nothing
// about what a Godot export pulls in. So this checks the four places an asset
// can actually escape:
//
//   1. the index          - what is about to be committed
//   2. the working tree   - what git currently tracks
//   3. the whole history  - what a push would carry, including old commits
//   4. the export presets - what a build would compile in
//
// Run from a pre-commit hook, a pre-push hook and CI, so one implementation
// covers every moment an asset could leave the machine.

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

// Everything under here is third-party and must stay local.
const GUARDED = "game/assets/species/brawl_arena";

const args = new Set(process.argv.slice(2));
const stagedOnly = args.has("--staged");
const quiet = args.has("--quiet");

function git(...argv) {
  try {
    return execFileSync("git", argv, { encoding: "utf8" });
  } catch {
    return "";
  }
}

function lines(text) {
  return text.split("\n").map((line) => line.trim()).filter(Boolean);
}

const failures = [];

// 1. About to be committed.
const staged = lines(git("diff", "--cached", "--name-only")).filter((p) =>
  p.startsWith(GUARDED)
);
if (staged.length) {
  failures.push({
    what: `${staged.length} species file(s) staged for commit`,
    sample: staged.slice(0, 5),
    fix: `git restore --staged ${GUARDED}`,
  });
}

if (!stagedOnly) {
  // 2. Currently tracked.
  const tracked = lines(git("ls-files", "--", GUARDED));
  if (tracked.length) {
    failures.push({
      what: `${tracked.length} species file(s) tracked in the working tree`,
      sample: tracked.slice(0, 5),
      fix: `git rm -r --cached ${GUARDED}`,
    });
  }

  // 3. Anywhere in history. A push carries old commits too, so a file removed
  //    today is still published if it was ever committed.
  const historical = new Set(
    lines(git("log", "--all", "--pretty=format:", "--name-only", "--", GUARDED))
  );
  if (historical.size) {
    failures.push({
      what: `${historical.size} species path(s) present somewhere in history`,
      sample: [...historical].slice(0, 5),
      fix: "history rewrite required - git filter-repo, then force-push",
    });
  }

  // 4. What a build would include. Godot follows scene dependencies, so a
  //    species dragged into a game scene ships with the export unless the
  //    preset excludes it outright.
  if (existsSync("export_presets.cfg")) {
    const config = readFileSync("export_presets.cfg", "utf8");
    const presets = config.split(/^\[preset\.\d+\]$/m).slice(1);
    presets.forEach((preset, index) => {
      const name = /name="([^"]*)"/.exec(preset)?.[1] ?? `preset ${index}`;
      const exclude = /exclude_filter="([^"]*)"/.exec(preset)?.[1] ?? "";
      if (!exclude.includes(GUARDED)) {
        failures.push({
          what: `export preset ${name} does not exclude the species`,
          sample: [`exclude_filter="${exclude}"`],
          fix: `add ${GUARDED}/* to that preset's exclude_filter`,
        });
      }
    });
  }
}

if (!failures.length) {
  if (!quiet) {
    console.log(`species guard: clean (${GUARDED} is not in the index, ` +
      "the tree, the history, or any export preset)");
  }
  process.exit(0);
}

console.error("\nSPECIES GUARD FAILED\n");
console.error("Third-party assets must never leave this machine.\n");
for (const failure of failures) {
  console.error(`  ${failure.what}`);
  for (const item of failure.sample) console.error(`      ${item}`);
  console.error(`    fix: ${failure.fix}\n`);
}
process.exit(1);
