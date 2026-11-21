// Fails when a JavaScript module doesn't parse, including pages no test imports.
//
//   node <boundary>/scripts/check-modules.mjs <folder>...
//
// Every .js and .mjs file under each folder is read as an ES module. Plain `node --check file.js`
// isn't enough: outside a package that says "type": "module", Node guesses a file's kind, and a
// broken file that has an import or export passes with exit 0. So each file goes to Node on stdin
// with --input-type=module, which fails it.

import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const folders = process.argv.slice(2);
if (!folders.length) {
  console.error("usage: node check-modules.mjs <folder>...");
  process.exit(2);
}

function files(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const path = join(dir, e.name);
    if (e.isDirectory()) return e.name === "node_modules" ? [] : files(path);
    return /\.m?js$/.test(e.name) ? [path] : [];
  });
}

let checked = 0;
let broken = 0;
for (const folder of folders) {
  if (!statSync(folder, { throwIfNoEntry: false })?.isDirectory()) {
    console.error(`modules: no folder ${folder}`);
    broken++;
    continue;
  }
  for (const file of files(folder)) {
    checked++;
    const r = spawnSync(process.execPath, ["--input-type=module", "--check"], { input: readFileSync(file, "utf8"), encoding: "utf8" });
    if (r.status !== 0) {
      broken++;
      console.error(`modules: ${file} doesn't parse`);
      console.error(r.stderr.split("\n").filter((l) => l.trim()).slice(0, 4).map((l) => `  ${l}`).join("\n"));
    }
  }
}
console.log(`modules: ${checked} checked, ${broken} broken`);
process.exit(broken ? 1 : 0);
