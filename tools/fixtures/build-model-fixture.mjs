#!/usr/bin/env node
// Builds the test model: a valid .glb carrying named animations and nothing else
// (spec 16, section 10).
//
// Generated rather than authored, and generated rather than borrowed. The
// species models never leave one machine (decision 0027), so a test that
// opened one could not run in CI — and a fixture nobody can regenerate is a
// fixture nobody can change.
//
// What the clip tests read is the animation names, and the point of the file is
// that a real glTF parser has to agree they are there. It also carries a quad
// and a one-pixel texture, so the budget report has something to count — a
// fixture with no geometry would let a reporter that measures nothing pass.

import { writeFileSync, mkdirSync } from "node:fs";
import { deflateSync } from "node:zlib";
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
const USHORT = 5123;
const TIMES = [0, 1];
const TRANSLATIONS = [0, 0, 0, 0, 1, 0];

/// A quad: four corners, two triangles. Two rather than one so a triangle count
/// cannot be confused with a count of primitives.
const POSITIONS = [0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0];
const INDICES = [0, 1, 2, 0, 2, 3];
const TRIANGLES = INDICES.length / 3;

/// One opaque pixel. The smallest thing that is genuinely a PNG — the budget
/// report has to measure a texture, and a fixture with none would let a reporter
/// that measures nothing pass for a model under budget.
function onePixelPng() {
  const chunk = (type, body) => {
    const length = Buffer.alloc(4);
    length.writeUInt32BE(body.length);
    const typed = Buffer.concat([Buffer.from(type, "ascii"), body]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(typed));
    return Buffer.concat([length, typed, crc]);
  };

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(1, 0);   // width
  ihdr.writeUInt32BE(1, 4);   // height
  ihdr[8] = 8;                // bit depth
  ihdr[9] = 2;                // colour type: truecolour
  const raw = Buffer.from([0x00, 0xc8, 0x40, 0x20]); // filter byte, then one RGB pixel

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

/// Everything the file needs, laid out once so the offsets are computed rather
/// than written down. A hand-kept offset table is the classic way a fixture
/// starts lying about itself.
function layout() {
  const png = onePixelPng();
  const parts = [
    { name: "times", bytes: floats(TIMES) },
    { name: "translations", bytes: floats(TRANSLATIONS) },
    { name: "positions", bytes: floats(POSITIONS) },
    { name: "indices", bytes: ushorts(INDICES) },
    { name: "png", bytes: png },
  ];

  const views = [];
  let offset = 0;
  const chunks = [];
  for (const part of parts) {
    const padding = (4 - (offset % 4)) % 4;
    if (padding) { chunks.push(Buffer.alloc(padding)); offset += padding; }
    views.push({ buffer: 0, byteOffset: offset, byteLength: part.bytes.length });
    chunks.push(part.bytes);
    offset += part.bytes.length;
  }

  return { bin: Buffer.concat(chunks), views };
}

function floats(values) {
  const bytes = Buffer.alloc(values.length * 4);
  values.forEach((v, i) => bytes.writeFloatLE(v, i * 4));
  return bytes;
}

function ushorts(values) {
  const bytes = Buffer.alloc(values.length * 2);
  values.forEach((v, i) => bytes.writeUInt16LE(v, i * 2));
  return bytes;
}

/// Every clip shares one pair of accessors. They differ only in name, which is
/// the whole subject of the tests that read this. The quad and its texture are
/// there so the budget report has something real to count.
function document(bin, views) {
  const corners = [];
  for (let i = 0; i < POSITIONS.length; i += 3) corners.push(POSITIONS.slice(i, i + 3));

  return {
    asset: { version: "2.0", generator: "voltari build-model-fixture" },
    scene: 0,
    scenes: [{ nodes: [0] }],
    nodes: [{ name: "Root", mesh: 0 }],
    buffers: [{ byteLength: bin.length }],
    bufferViews: [
      views[0],
      views[1],
      views[2],
      { ...views[3], target: 34963 },
      views[4],
    ],
    accessors: [
      {
        bufferView: 0, componentType: FLOAT, count: TIMES.length, type: "SCALAR",
        min: [Math.min(...TIMES)], max: [Math.max(...TIMES)],
      },
      { bufferView: 1, componentType: FLOAT, count: TIMES.length, type: "VEC3" },
      {
        bufferView: 2, componentType: FLOAT, count: corners.length, type: "VEC3",
        min: [0, 0, 0], max: [1, 1, 0],
      },
      { bufferView: 3, componentType: USHORT, count: INDICES.length, type: "SCALAR" },
    ],
    images: [{ bufferView: 4, mimeType: "image/png" }],
    textures: [{ source: 0 }],
    materials: [{ pbrMetallicRoughness: { baseColorTexture: { index: 0 } } }],
    meshes: [{
      name: "Quad",
      primitives: [{ attributes: { POSITION: 2 }, indices: 3, material: 0 }],
    }],
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
  const { bin, views } = layout();
  const json = Buffer.from(JSON.stringify(document(bin, views)), "utf8");

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
  console.log(`model fixture: ${CLIPS.length} clips, ${TRIANGLES} triangles, 1 texture -> ${OUT}`);
}

main();
