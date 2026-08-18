// Emits the case tables straight out of the engine this library is a port of.
//
// Python's unicodedata is a version or two behind whatever ICU the runtime was
// built against, and every mismatch the parity run found was a case pair added
// in a newer Unicode. So the case data comes from here and the normalization
// data stays with Python, where the tables it needs (combining class, canonical
// decomposition) are stable by Unicode's own policy and not reachable from JS.
//
// `cased` and `caseIgnorable` are not exposed as properties in JS either. They
// are recovered by probing the one rule that reads them: sigma lowercases to a
// final form only at the end of a word, so a sigma with a probe character on one
// side reports that character's property in its own output.
import { writeFileSync } from "fs";

const A = "Α", S = "Σ", FINAL = "ς";
const h = (v) => v.toString(16);

const lowerRuns = [];
const lowerx = [];
const casedSet = [];
const ignorableSet = [];

const simple = [];
for (let cp = 0; cp <= 0x10ffff; cp++) {
  if (cp >= 0xd800 && cp <= 0xdfff) continue;
  const c = String.fromCodePoint(cp);
  const l = c.toLowerCase();
  if (l !== c) {
    const pts = [...l].map((x) => x.codePointAt(0));
    if (pts.length === 1) simple.push([cp, pts[0] - cp]);
    else lowerx.push([cp, pts]);
  }
  // Cased: does a sigma in front of this character stop being final?
  const cased = (A + S + c).toLowerCase()[1] !== FINAL;
  // Case_Ignorable: does a sigma behind it still see the cased alpha?
  const seen = (A + c + S).toLowerCase().endsWith(FINAL);
  if (cased) casedSet.push(cp);
  else if (seen) ignorableSet.push(cp);
}

// (start, count, stride, delta) runs, preferring whichever stride covers more.
for (let i = 0; i < simple.length; ) {
  const [cp, d] = simple[i];
  let best = [1, 1];
  for (const stride of [1, 2]) {
    let n = 1;
    while (
      i + n < simple.length &&
      simple[i + n][0] === cp + n * stride &&
      simple[i + n][1] === d
    ) n++;
    if (n > best[1]) best = [stride, n];
  }
  const [stride, n] = best;
  lowerRuns.push([cp, n, stride, d]);
  i += n;
}

const setRuns = (list) => {
  const out = [];
  for (let i = 0; i < list.length; ) {
    let n = 1;
    while (i + n < list.length && list[i + n] === list[i] + n) n++;
    out.push([list[i], n]);
    i += n;
  }
  return out;
};

writeFileSync(
  "/tmp/case_tables.json",
  JSON.stringify({
    lower: lowerRuns.map(([s, n, st, d]) => `${h(s)}:${h(n)}:${h(st)}:${d < 0 ? "-" + h(-d) : h(d)}`).join(" "),
    lowerx: lowerx.map(([cp, pts]) => `${h(cp)}:${pts.map(h).join(",")}`).join(" "),
    cased: setRuns(casedSet).map(([s, n]) => `${h(s)}:${h(n)}`).join(" "),
    ignorable: setRuns(ignorableSet).map(([s, n]) => `${h(s)}:${h(n)}`).join(" "),
  })
);
console.log("lower runs", lowerRuns.length, "lowerx", lowerx.length,
            "cased runs", setRuns(casedSet).length,
            "ignorable runs", setRuns(ignorableSet).length);
