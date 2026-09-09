#!/usr/bin/env node
// Builds the test model: a valid .glb carrying named animations and nothing else
// (spec 16, section 10).
//
// Generated rather than authored, and generated rather than borrowed. The
// placeholder models never leave one machine (decision 0027), so a test that
// opened one could not run in CI — and a fixture nobody can regenerate is a
// fixture nobody can change.
//
// The geometry is one node and two keyframes. Nothing here is looked at; what
// the tests read is the animation names, and the point of the file is that a
// real glTF parser has to agree they are there.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "..", "tests", "fixtures", "models", "clip_shapes.glb");

/// One clip per shape the resolver has to handle, and no filler. Each of these
/// exists because getting it wrong is a real failure, not to pad the file.
const CLIPS = [
  "ba10_waitA01",              // a slot's first take
  "ba10_waitB01",              // a second take of the same slot
  "ba20_buturi01",             // another slot
  "ba20_buturi01_1",           // conversion noise: the same take, again
  "ba21_tokusyu01_FBX_OVERRIDE", // conversion noise, the other spelling
  "damageS01",                 // the bare legacy name, no code at all
  "ba41_down01_FX",            // an effect track, played alongside its slot
  "kw32_happyA01",             // the companion set
  "ba10_adjustear",            // a known code, an unknown word: an extra
  "HideLeftEar",               // not an animation at all: a stow clip
];

const FLOAT = 5126;
const TIMES = [0, 1];
const TRANSLATIONS = [0, 0, 0, 0, 1, 0];

function binary() {
  const bytes = Buffer.alloc((TIMES.length + TRANSLATIONS.length) * 4);
  TIMES.forEach((v, i) => bytes.writeFloatLE(v, i * 4));
  TRANSLATIONS.forEach((v, i) => bytes.writeFloatLE(v, TIMES.length * 4 + i * 4));
  return bytes;
}

/// Every clip shares one pair of accessors. They differ only in name, which is
/// the whole subject of the tests that read this.
function document(binaryLength) {
  return {
    asset: { version: "2.0", generator: "voltari build-model-fixture" },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes: [{ name: "Root" }],
    buffers: [{ byteLength: binaryLength }],
    bufferViews: [
      { buffer: 0, byteOffset: 0, byteLength: TIMES.length * 4 },
      { buffer: 0, byteOffset: TIMES.length * 4, byteLength: TRANSLATIONS.length * 4 },
    ],
    accessors: [
      {
        bufferView: 0, componentType: FLOAT, count: TIMES.length, type: "SCALAR",
        min: [Math.min(...TIMES)], max: [Math.max(...TIMES)],
      },
      { bufferView: 1, componentType: FLOAT, count: TIMES.length, type: "VEC3" },
    ],
    animations: CLIPS.map((name) => ({
      name,
      samplers: [{ input: 0, output: 1, interpolation: "LINEAR" }],
      channels: [{ sampler: 0, target: { node: 0, path: "translation" } }],
    })),
  };
}

/// A chunk is padded to four bytes with its own filler: spaces for JSON so it
/// stays parseable, zeros for binary. Getting the filler wrong produces a file
/// that most readers accept and one does not, which is the worst outcome.
function chunk(payload, type, filler) {
  const padding = (4 - (payload.length % 4)) % 4;
  const body = Buffer.concat([payload, Buffer.alloc(padding, filler)]);
  const header = Buffer.alloc(8);
  header.writeUInt32LE(body.length, 0);
  header.writeUInt32LE(type, 4);
  return Buffer.concat([header, body]);
}

function main() {
  const bin = binary();
  const json = Buffer.from(JSON.stringify(document(bin.length)), "utf8");

  const chunks = Buffer.concat([
    chunk(json, 0x4e4f534a, 0x20),
    chunk(bin, 0x004e4942, 0x00),
  ]);

  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0); // "glTF"
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(header.length + chunks.length, 8);

  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, Buffer.concat([header, chunks]));
  console.log(`model fixture: ${CLIPS.length} clips -> ${OUT}`);
}

main();
