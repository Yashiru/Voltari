#!/usr/bin/env node
// What the assets cost, read against a budget (spec 16, section 7).
//
// It reports and refuses nothing (decision 0048). A ceiling would have to be
// invented, since nobody has profiled this game on a device, and a wrong ceiling
// is worse than none because it gets worked around rather than questioned.
//
// **No frame rate is predicted.** "This composition is at 140% of mid" is a fact
// about the assets. "This will run at 42 fps" would be a guess wearing the
// authority of a measurement, which is the failure this whole tool is about.
//
//   node tools/budget/report-budget.mjs <file-or-directory>...
//
// Reads .glb directly rather than through Godot: the numbers wanted here are in
// the glTF document, and a tool that needed the editor could not run in CI.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const TIERS = JSON.parse(readFileSync(join(HERE, "tiers.json"), "utf8"));

const GLB_MAGIC = 0x46546c67;
const JSON_CHUNK = 0x4e4f534a;
const TRIANGLES_MODE = 4; // glTF's default primitive mode

/// The JSON half of a .glb. Everything measured here lives in it.
function document(path) {
  const bytes = readFileSync(path);
  if (bytes.length < 20 || bytes.readUInt32LE(0) !== GLB_MAGIC) {
    throw new Error(`${path} is not a .glb`);
  }
  const length = bytes.readUInt32LE(12);
  if (bytes.readUInt32LE(16) !== JSON_CHUNK) throw new Error(`${path}: no JSON chunk`);
  return JSON.parse(bytes.subarray(20, 20 + length).toString("utf8"));
}

/// Indexed geometry counts its indices; unindexed counts its positions. Missing
/// that second case would report zero for a whole class of model, which is the
/// quiet failure a budget tool can have.
function triangles(gltf) {
  let total = 0;
  for (const mesh of gltf.meshes ?? []) {
    for (const primitive of mesh.primitives ?? []) {
      if ((primitive.mode ?? TRIANGLES_MODE) !== TRIANGLES_MODE) continue;
      const source = primitive.indices !== undefined
        ? gltf.accessors?.[primitive.indices]
        : gltf.accessors?.[primitive.attributes?.POSITION];
      total += Math.floor((source?.count ?? 0) / 3);
    }
  }
  return total;
}

/// The bytes an image occupies, embedded or beside the model.
///
/// The library embeds them; the sibling PNGs beside a model are Godot's import
/// artefacts, not the source. The external branch is here because glTF allows
/// it and a fakemon may well ship that way — not because anything does today.
///
/// Not what it costs decoded on the GPU, which depends on the import settings.
/// Stated rather than implied, so nobody reads this as VRAM.
function textureBytes(gltf, path) {
  let total = 0;
  const beside = dirname(path);

  for (const image of gltf.images ?? []) {
    if (image.bufferView !== undefined) {
      total += gltf.bufferViews?.[image.bufferView]?.byteLength ?? 0;
      continue;
    }
    if (typeof image.uri !== "string" || image.uri.startsWith("data:")) continue;
    try {
      total += statSync(join(beside, decodeURIComponent(image.uri))).size;
    } catch {
      // A texture the model names and the disk has not got. Not this tool's to
      // report — the manifest validation is where a missing file is an error.
    }
  }
  return total;
}

/// The second colouring: one texture per surface in a `shiny/` folder beside the
/// model, named by the clip sidecar rather than by the glTF (spec 16).
///
/// Counted apart on purpose. A shiny **replaces** a surface's texture rather
/// than adding to it, so it costs a scene nothing — but every one of them ships,
/// so it costs the package everything. Folding the two together would answer
/// neither question.
function shinyBytes(path) {
  const folder = join(dirname(path), "shiny");
  let total = 0;
  try {
    for (const entry of readdirSync(folder)) {
      if (entry.endsWith(".png")) total += statSync(join(folder, entry)).size;
    }
  } catch {
    // No second colouring. The common case, and not a defect.
  }
  return total;
}

function joints(gltf) {
  return Math.max(0, ...(gltf.skins ?? []).map((skin) => skin.joints?.length ?? 0));
}

function measure(path) {
  const gltf = document(path);
  return {
    name: basename(path, ".glb"),
    triangles: triangles(gltf),
    textureBytes: textureBytes(gltf, path),
    shinyBytes: shinyBytes(path),
    joints: joints(gltf),
    clips: (gltf.animations ?? []).length,
  };
}

function models(paths) {
  const found = [];
  for (const path of paths) {
    if (statSync(path).isDirectory()) {
      for (const entry of readdirSync(path)) {
        const child = join(path, entry);
        if (statSync(child).isDirectory()) found.push(...models([child]));
        else if (entry.endsWith(".glb")) found.push(child);
      }
    } else if (path.endsWith(".glb")) {
      found.push(path);
    }
  }
  return found;
}

const mb = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;

/// A decimal below one percent. Rounding 0.2% and 0.4% both to "0%" hides the
/// only thing the number is for — which way the trend is going.
function share(used, budget) {
  const percent = (used / budget) * 100;
  const shown = percent < 10 ? percent.toFixed(1) : String(Math.round(percent));
  return `${shown.padStart(5)}%`;
}

/// The average creature times the composition, which is the number that decides
/// whether a scene fits. A single model's figure never does.
function report(measured) {
  const total = measured.reduce(
    (sum, m) => ({
      triangles: sum.triangles + m.triangles,
      textureBytes: sum.textureBytes + m.textureBytes,
      shinyBytes: sum.shinyBytes + m.shinyBytes,
    }),
    { triangles: 0, textureBytes: 0, shinyBytes: 0 },
  );
  const shinies = measured.filter((m) => m.shinyBytes > 0).length;

  console.log(`${measured.length} model(s)`);
  console.log(`  triangles       ${total.triangles}`);
  console.log(`  texture bytes   ${mb(total.textureBytes)} (in file, not decoded)`);
  console.log(`  most joints     ${Math.max(0, ...measured.map((m) => m.joints))}`);
  console.log(`  clips           ${measured.reduce((n, m) => n + m.clips, 0)}`);
  if (shinies > 0) {
    const extra = Math.round((total.shinyBytes / total.textureBytes) * 100);
    console.log(
      `  second colouring ${mb(total.shinyBytes)} across ${shinies} model(s)`
      + ` — ${extra}% on top of the textures above, shipped whether worn or not`,
    );
  }

  const each = TIERS.composition.creatures;
  const scene = {
    triangles: Math.round((total.triangles / measured.length) * each),
    textureBytes: Math.round((total.textureBytes / measured.length) * each),
  };

  console.log(`\nA scene of ${each} creatures — ${TIERS.composition.why}:`);
  for (const tier of TIERS.tiers) {
    console.log(
      `  ${tier.name.padEnd(5)} ${share(scene.triangles, tier.triangles)} of triangles`
      + `  ${share(scene.textureBytes, tier.texture_bytes)} of texture budget`
      + `   (${tier.stands_for})`,
    );
  }
  console.log("\nA shiny replaces a surface's texture rather than adding one, so it costs");
  console.log("a scene nothing and the download everything.");
  console.log("\nProvisional budgets: no device has been profiled. No frame rate is implied.");

  return total;
}

function main() {
  const paths = process.argv.slice(2);
  if (paths.length === 0) {
    console.error("usage: report-budget.mjs <file-or-directory>...");
    process.exit(2);
  }

  const found = models(paths);
  if (found.length === 0) {
    console.error("no .glb found — nothing was measured");
    process.exit(1);
  }

  const total = report(found.map(measure));

  // A reporter that silently measures nothing looks exactly like a roster under
  // budget, which is the one way this tool could be actively harmful.
  if (total.triangles === 0) {
    console.error("\nmeasured 0 triangles across every model — the reader is wrong, not the assets");
    process.exit(1);
  }
}

main();
