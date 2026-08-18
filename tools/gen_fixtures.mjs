// Renders the original library across a wide slice of its input space and writes
// what it produced, so `test/parity.lua` can diff the port against it.
//
// Run from a checkout of the upstream repo:
//   node tools/gen_fixtures.mjs /path/to/blobatar/packages/blobatar/src
//
// Requires a TypeScript-capable runtime (bun, or node with type stripping).
import { writeFileSync } from "fs";

const SRC = process.argv[2] || "/tmp/blobatar/packages/blobatar/src";
const { blobatar, _layout } = await import(SRC + "/blobatar.ts");
const EX = await import(SRC + "/expression.ts");

const COUNT = Number(process.argv[3] || 3000);
const NAMES = [];
for (let i = 0; i < COUNT; i++) NAMES.push("seed-" + i);
for (const s of [
  "", "a", "alain", "alain@example.com", "Alain@Example.COM", "  padded  ",
  "café", "café", "日本語", "😀🎈", "ΟΔΟΣ", "İstanbul", "x".repeat(120),
  "user_1234", "0", "-1", ".", "team/repo", "a b c",
]) NAMES.push(s);

const OPTS = [
  {},
  { size: 64 },
  { size: 48, title: "A & B <c>" },
  { background: true },
  { background: "square" },
  { background: "circle" },
  { background: "squircle" },
  { hue: 0 },
  { hue: 210, tone: 0.95 },
  { tone: 0.05 },
  { contrast: false },
  { normalize: false },
  { palette: { head: "#123456", eye: "#fedcba" } },
  { traits: { shape: 0.95 } },
  { traits: { shape: 0.5, "eye.gap": 0.99, "eye.ratio": 0, "eye.scale": 1 } },
  { traits: { shape: 0.8, "nub.n": 0.99 } },
  { traits: { shape: 0.9 } },
  { traits: { shape: 0.3, "body.pts": 0.99 } },
];

const EXPRS = ["idle", "happy", "sad", "mad", "surprised", "wink", "sleepy",
               "smug", "unsure", "scared", "love", "shy", "sick"];

// Tab separated, with only the seed and the option set hex-encoded: those are
// the two fields that can contain anything. Payloads go in raw, which halves the
// file and makes a failing row readable without a decoder.
const rows = [];
const enc = (s) => Buffer.from(s, "utf8").toString("hex");
const row = (...f) => rows.push(f.join("\t"));

// One pass over every option set, cycling names so the whole space gets covered
// without the cross product exploding.
let i = 0;
for (const o of OPTS) {
  for (let k = 0; k < Math.max(20, COUNT / 14) ; k++) {
    const name = NAMES[i++ % NAMES.length];
    row("S", enc(name), enc(JSON.stringify(o)), blobatar(name, o));
  }
}

// Every expression against every name, static.
for (const e of EXPRS) {
  for (let k = 0; k < Math.max(20, COUNT / 12) ; k++) {
    const name = NAMES[i++ % NAMES.length];
    const o = { expression: EX[e] };
    row("E", enc(name), e, blobatar(name, o));
  }
}

// The numeric layout, which carries values the markup rounds away.
for (let k = 0; k < Math.max(60, COUNT / 3.5) ; k++) {
  const name = NAMES[i++ % NAMES.length];
  const e = EXPRS[k % EXPRS.length];
  const l = _layout(name, { expression: EX[e] });
  const f = (v) => v.toFixed(12);
  const parts = [
    l.shape, f(l.body.cx), f(l.body.cy), f(l.body.rx), f(l.body.ry),
    f(l.body.n), f(l.body.rot), l.body.radii.map(f).join(","),
    l.petals.map((p) => [f(p.cx), f(p.cy), f(p.r)].join(",")).join(";") || "-",
    l.eyes.map((y) => [f(y.cx), f(y.cy), f(y.rx), f(y.ry), f(y.n), f(y.rot)].join(",")).join(";"),
    l.palette.bg, l.palette.head, l.palette.eye,
  ].join(" ");
  row("L", enc(name), e, parts);
}

// The motion custom properties, which the LOVE renderer reads as numbers.
const { motionVars } = await import(SRC + "/animate.ts");
const { traits } = await import(SRC + "/traits.ts");
for (let k = 0; k < Math.max(40, COUNT / 5) ; k++) {
  const name = NAMES[i++ % NAMES.length];
  const v = motionVars(traits(name));
  row("M", enc(name), "-", Object.entries(v).map(([a, b]) => a + ":" + b).join(";"));
}

// The pose custom properties, which pin the channel values and their order.
for (const e of EXPRS) {
  const v = EX[e].vars(EX[e].p);
  row("P", "-", e, Object.entries(v).map(([a, b]) => a + ":" + b).join(";"));
}

writeFileSync(process.env.FIXTURE_OUT || "test/fixtures.txt", rows.join("\n"));
console.log("fixture rows", rows.length);
