#!/usr/bin/env node
// Mutation harness for the simulation core (decision 0014).
//
// Injects a defect, runs the suite, and records whether the suite noticed. A
// surviving mutant is a hole in the tests, not a bug in the code — which is why
// this is the metric that replaced line coverage as the objective (0005).
//
// On demand, never in CI. Expected to be run, and its score recorded in the
// pull request, for any change touching the effect system or the turn machine.
//
// Usage:
//   node tools/mutation/mutate.mjs [--limit N] [--seed N] [--list] [--file SUBSTRING]
//
// `--file` narrows to paths CONTAINING SUBSTRING, which is how a module gets
// covered exhaustively rather than sampled. Raise --limit alongside it: a
// sampled score for one file is noise, and the point of narrowing is to stop
// sampling.
//
// It is a substring, not a filename — `--file damage.gd` also matches
// log_damage.gd. The run prints the files it selected, so read that rather than
// assuming the filter meant one file.

import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { execFileSync, spawn } from "node:child_process";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { readdirSync, statSync } from "node:fs";
import { stripCommentsAndStrings, collectScripts } from "../lib/gdscript.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const CORE_DIRS = ["addons/voltari/core", "addons/voltari/loaders"];

// Each operator rewrites one token into another that is still valid GDScript
// but means something different. Anything the tests do not distinguish is a gap
// they should have closed.
const OPERATORS = [
  { name: "comparison", from: /(?<![<>=!+\-*/])<(?![<=])/g, to: "<=" },
  { name: "comparison", from: /(?<![<>=!+\-*/])>(?![>=])/g, to: ">=" },
  { name: "equality", from: /==/g, to: "!=" },
  { name: "equality", from: /!=/g, to: "==" },
  { name: "arithmetic", from: /(?<![+\-*/=<>!])\+(?![+=])/g, to: "-" },
  { name: "arithmetic", from: /(?<![+\-*/=<>!])-(?![-=>])/g, to: "+" },
  { name: "arithmetic", from: /(?<![*/])\*(?![*=])/g, to: "/" },
  { name: "boolean", from: /\band\b/g, to: "or" },
  { name: "boolean", from: /\bor\b/g, to: "and" },
  { name: "boolean", from: /\bnot\b/g, to: "" },
  { name: "literal", from: /\btrue\b/g, to: "false" },
  { name: "literal", from: /\bfalse\b/g, to: "true" },
];

function parseArgs(argv) {
  const args = { limit: 40, seed: 1, list: false, file: "" };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--limit") args.limit = Number(argv[++i]);
    else if (argv[i] === "--seed") args.seed = Number(argv[++i]);
    else if (argv[i] === "--list") args.list = true;
    else if (argv[i] === "--file") args.file = argv[++i];
  }
  return args;
}

// Deterministic ordering, so a run is reproducible and two runs on the same
// code compare like for like.
function shuffled(items, seed) {
  let state = seed >>> 0 || 1;
  const next = () => {
    state ^= (state << 13) >>> 0;
    state ^= state >>> 17;
    state ^= (state << 5) >>> 0;
    return state >>> 0;
  };
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = next() % (i + 1);
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

// Mutation sites are found on code with comments and strings blanked out, then
// applied to the original text at the same offsets — so a `+` inside a comment
// is never a candidate, and the file stays byte-identical elsewhere.
function mutantsFor(path, source) {
  const code = stripCommentsAndStrings(source);
  const found = [];

  for (const operator of OPERATORS) {
    for (const match of code.matchAll(operator.from)) {
      const line = source.slice(0, match.index).split("\n").length;
      found.push({
        path,
        line,
        operator: operator.name,
        offset: match.index,
        length: match[0].length,
        replacement: operator.to,
        was: match[0],
      });
    }
  }

  return found;
}

function applyMutant(source, mutant) {
  return (
    source.slice(0, mutant.offset) +
    mutant.replacement +
    source.slice(mutant.offset + mutant.length)
  );
}

// A clean run of the suite takes about three seconds, so this is generous by a
// factor of forty. It is sized for a run that HANGS rather than fails: at the
// previous fifteen-minute limit, one stalled run cost more than a whole
// exhaustive pass, which is what --file exists to make practical.
//
// Too low would be worse than too high — a legitimate slow run counted as
// caught hides a survivor instead of reporting one.
const SUITE_TIMEOUT_MS = 120 * 1000;

/// "survived" (the suite still passed), "caught" (it failed), or "hung" (it
/// never finished). Hanging is caught too, but it is a different fact and the
/// report keeps them apart.
///
/// The child is put in its own process GROUP and the group is what gets killed.
///
/// What we launch is a wrapper script that spawns Godot, so signalling the
/// wrapper alone leaves Godot running. Each survivor then holds a core at 100%
/// and they accumulate over a long pass until the machine is starved — which
/// reads as "mutation testing is slow" rather than as the leak it is. Neither
/// Node's own `timeout` option nor coreutils `timeout` reliably reached the
/// grandchild here; both were tried and both left Godot alive.
function runSuite(root, godot) {
  return new Promise((resolve) => {
    const child = spawn(
      "./addons/gdUnit4/runtest.sh",
      ["--headless", "--ignoreHeadlessMode", "--continue", "-a", "tests"],
      {
        cwd: root,
        env: { ...process.env, GODOT_BIN: godot },
        stdio: "ignore",
        detached: true, // makes the child a group leader, so -pid reaches the tree
      },
    );

    let timedOut = false;
    const deadline = setTimeout(() => {
      timedOut = true;
      try {
        process.kill(-child.pid, "SIGKILL");
      } catch {
        // Already gone between the timer firing and the signal.
      }
    }, SUITE_TIMEOUT_MS);

    child.on("exit", (code) => {
      clearTimeout(deadline);
      if (timedOut) resolve("hung");
      else resolve(code === 0 ? "survived" : "caught");
    });

    child.on("error", () => {
      clearTimeout(deadline);
      resolve("caught");
    });
  });
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const godot = (() => {
    try {
      return execFileSync("which", ["godot"], { encoding: "utf8" }).trim();
    } catch {
      console.error("godot is not on the PATH; the harness needs it to run the suite.");
      process.exit(1);
    }
  })();

  const all = [];
  for (const dir of CORE_DIRS) {
    const absolute = join(REPO, dir);
    if (!existsSync(absolute)) continue;
    for (const path of collectScripts(absolute, readdirSync, statSync, join)) {
      all.push(...mutantsFor(path, readFileSync(path, "utf8")));
    }
  }

  const scoped = args.file ? all.filter((mutant) => mutant.path.includes(args.file)) : all;
  if (args.file && scoped.length === 0) {
    console.error(`no mutation site matches "${args.file}".`);
    process.exit(1);
  }

  const selected = shuffled(scoped, args.seed).slice(0, args.limit);
  const scope = args.file ? `matching "${args.file}"` : "in the core";
  console.log(`${scoped.length} mutation site(s) ${scope}; running ${selected.length}.`);

  if (args.file) {
    // Named, because the filter is a substring and may have caught more files
    // than the one that was meant.
    const files = [...new Set(scoped.map((mutant) => relative(REPO, mutant.path)))].sort();
    for (const file of files) {
      const count = scoped.filter((mutant) => relative(REPO, mutant.path) === file).length;
      console.log(`  ${file} (${count})`);
    }
  }
  if (selected.length < scoped.length) {
    console.log(`  (${scoped.length - selected.length} not run — raise --limit for an exhaustive pass.)`);
  }

  if (args.list) {
    for (const mutant of selected) {
      console.log(`  ${relative(REPO, mutant.path)}:${mutant.line}  ${mutant.was} -> ${mutant.replacement || "(removed)"}`);
    }
    return;
  }

  // A copy, so a crash mid-run cannot leave the real tree mutated.
  const sandbox = mkdtempSync(join(tmpdir(), "voltari-mutation-"));
  const root = join(sandbox, "repo");
  cpSync(REPO, root, {
    recursive: true,
    filter: (source) => !source.includes("/.git") && !source.includes("node_modules"),
  });

  // The baseline must be green, or every mutant would read as caught.
  if ((await runSuite(root, godot)) !== "survived") {
    console.error("The suite fails before any mutation. Fix that first.");
    rmSync(sandbox, { recursive: true, force: true });
    process.exit(1);
  }

  const survivors = [];
  let caught = 0;
  let hung = 0;

  for (const [index, mutant] of selected.entries()) {
    const target = join(root, relative(REPO, mutant.path));
    const original = readFileSync(target, "utf8");
    writeFileSync(target, applyMutant(original, mutant));

    const verdict = await runSuite(root, godot);
    writeFileSync(target, original);

    if (verdict === "survived") survivors.push(mutant);
    else caught++;
    if (verdict === "hung") hung++;

    const label = verdict === "survived" ? "SURVIVED" : verdict;
    process.stdout.write(
      `  [${index + 1}/${selected.length}] ${label.padEnd(8)} ` +
        `${relative(REPO, mutant.path)}:${mutant.line} ${mutant.was} -> ${mutant.replacement || "(removed)"}\n`,
    );
  }

  rmSync(sandbox, { recursive: true, force: true });

  const score = selected.length > 0 ? (caught / selected.length) * 100 : 0;
  console.log(`\nmutation score: ${score.toFixed(1)}%  (${caught} caught, ${survivors.length} survived)`);

  if (hung > 0) {
    console.log(
      `${hung} of those hung the suite rather than failing it — an unbounded loop, not a broken assertion.`,
    );
  }

  if (survivors.length > 0) {
    console.log("\nSurvivors — each is a test the suite does not have:");
    for (const mutant of survivors) {
      console.log(
        `  ${relative(REPO, mutant.path)}:${mutant.line}  ${mutant.was} -> ${mutant.replacement || "(removed)"}`,
      );
    }
  }
}

await main();
