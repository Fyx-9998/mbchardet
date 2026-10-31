// Builds the browser demo into a directory (default: _site): compiles the
// demo package to JavaScript and copies it next to the page files.
//
//   node tools/build_demo.mjs [out-dir]
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const out = process.argv[2] ?? "_site";
execFileSync("moon", ["build", "--target", "js", "--release"], { stdio: "inherit" });
mkdirSync(out, { recursive: true });
// moon.work makes the root a workspace, which builds each module's packages
// under the module's name.
copyFileSync(
  join("_build", "js", "release", "build", "Fyx-9998", "mbchardet", "demo", "demo.js"),
  join(out, "mbchardet.js"),
);
for (const file of ["index.html", "app.js", "style.css"]) {
  copyFileSync(join("demo", file), join(out, file));
}
console.log(`demo written to ${out}/`);
