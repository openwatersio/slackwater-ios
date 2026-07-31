// Node control for the currents fit: same chs-bundle.js + chs-glue.js, same
// sample bytes as the JSCore run — constituents must match bit-for-bit.
import { readFileSync } from "node:fs";
import vm from "node:vm";
const R = "/Users/clarkbw/src/sailingnaturali/slackwater-ios/Slackwater/Resources";
const REP = process.argv[2]; // reports dir
const slug = process.argv[3] ?? "dodd-narrows";
const ctx = vm.createContext({ Date, Math, JSON });
vm.runInContext("var console={log(){},warn(){},error(){},info(){},debug(){}};", ctx);
vm.runInContext(readFileSync(`${R}/chs-bundle.js`, "utf8"), ctx);
vm.runInContext(readFileSync(`${R}/chs-glue.js`, "utf8"), ctx);
for (const w of ["210d", "60d"]) {
  ctx.__s = readFileSync(`${REP}/${slug}-${w}-samples.json`, "utf8");
  const node = JSON.parse(vm.runInContext("fitTides(__s)", ctx));
  const jscore = JSON.parse(readFileSync(`${REP}/${slug}-${w}-fit.json`, "utf8"));
  let worstAmp = 0, worstPhase = 0;
  for (let i = 0; i < node.constituents.length; i++) {
    const a = node.constituents[i], b = jscore.constituents[i];
    if (a.name !== b.name) { console.log(`${w}: ORDER MISMATCH at ${i}`); process.exit(1); }
    worstAmp = Math.max(worstAmp, Math.abs(a.amplitude - b.amplitude));
    worstPhase = Math.max(worstPhase, Math.abs(a.phase - b.phase));
  }
  const identical = worstAmp === 0 && worstPhase === 0 && node.offset === jscore.offset;
  console.log(`${w}: node vs JSCore — offset diff ${Math.abs(node.offset - jscore.offset)}, worst amp diff ${worstAmp}, worst phase diff ${worstPhase} => ${identical ? "BIT-IDENTICAL" : "DIFFERS"}`);
}
