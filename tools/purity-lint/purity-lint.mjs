#!/usr/bin/env node
// Purity lint for the Voltari simulation core.
//
// The core runs inside Godot but must use only the language, never the engine.
// See docs/architecture/layers.md, "Purity rule". A rule that is not enforced by
// CI decays, so this fails the build instead of relying on review.
//
// Usage: node tools/purity-lint/purity-lint.mjs [rootDir]

import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { stripCommentsAndStrings, collectScripts } from "../lib/gdscript.mjs";
import { join, relative } from "node:path";

const LINTED_DIRS = ["addons/voltari/core", "addons/voltari/rules"];

// Each rule is matched against source with comments and string literals removed,
// so a mention in prose or in a message identifier never trips the lint.
const FORBIDDEN = [
  { pattern: /\bNode[0-9A-Za-z_]*\b/, reason: "scene tree type" },
  { pattern: /\bSceneTree\b/, reason: "scene tree access" },
  { pattern: /\bget_tree\b/, reason: "scene tree access" },
  { pattern: /\bget_node\b/, reason: "scene tree access" },
  { pattern: /\bResource[0-9A-Za-z_]*\b/, reason: "Godot resource system" },
  { pattern: /\bawait\b/, reason: "asynchrony" },
  { pattern: /\bsignal\b/, reason: "signals; the core returns log events instead" },
  { pattern: /\bemit_signal\b/, reason: "signals; the core returns log events instead" },
  { pattern: /\brandi\b/, reason: "global RNG; inject a seeded stream" },
  { pattern: /\brandf\b/, reason: "global RNG; inject a seeded stream" },
  { pattern: /\brandomize\b/, reason: "global RNG; inject a seeded stream" },
  { pattern: /\brand_from_seed\b/, reason: "global RNG; inject a seeded stream" },
  { pattern: /\bRandomNumberGenerator\b/, reason: "global RNG; inject a seeded stream" },
  {
    pattern: /\bnext_in_range\b/,
    reason: "general-purpose draw; the core asks named decisions so that every source of chance stays enumerable",
  },
  { pattern: /\bTime\b/, reason: "clock access" },
  { pattern: /\bOS\b/, reason: "environment access" },
  { pattern: /\bEngine\b/, reason: "environment access" },
  { pattern: /\bFileAccess\b/, reason: "file I/O; data is injected by a loader" },
  { pattern: /\bDirAccess\b/, reason: "file I/O; data is injected by a loader" },
  { pattern: /\bload\s*\(/, reason: "file I/O; data is injected by a loader" },
  { pattern: /\bpreload\s*\(/, reason: "file I/O; data is injected by a loader" },
];

function lintFile(root, path) {
  const violations = [];
  const lines = stripCommentsAndStrings(readFileSync(path, "utf8")).split("\n");

  lines.forEach((line, index) => {
    for (const rule of FORBIDDEN) {
      const match = rule.pattern.exec(line);
      if (match !== null) {
        violations.push({
          file: relative(root, path),
          line: index + 1,
          symbol: match[0].trim(),
          reason: rule.reason,
        });
      }
    }
  });

  return violations;
}

function main() {
  const root = process.argv[2] ?? process.cwd();
  const violations = [];
  let scanned = 0;

  for (const dir of LINTED_DIRS) {
    const absolute = join(root, dir);
    if (!existsSync(absolute)) continue;
    for (const path of collectScripts(absolute, readdirSync, statSync, join)) {
      scanned++;
      violations.push(...lintFile(root, path));
    }
  }

  if (violations.length > 0) {
    console.error(`Purity lint: ${violations.length} violation(s).\n`);
    for (const v of violations) {
      console.error(`  ${v.file}:${v.line}  ${v.symbol}  — ${v.reason}`);
    }
    console.error("\nSee docs/architecture/layers.md, \"Purity rule\".");
    process.exit(1);
  }

  console.log(`Purity lint: clean (${scanned} file(s) scanned).`);
}

main();
