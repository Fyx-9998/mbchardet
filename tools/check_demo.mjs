// Checks a built demo (default: _site): that the page has its files, and
// that the compiled module gives the expected answers.
//
//   node tools/check_demo.mjs [site-dir]
import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const site = process.argv[2] ?? "_site";
for (const file of ["index.html", "app.js", "style.css", "mbchardet.js"]) {
  assert.ok(existsSync(join(site, file)), `${file} is missing`);
}
const { examine, decode_as, encoding_names } = await import(
  pathToFileURL(resolve(site, "mbchardet.js")).href
);

const bytes = (s) => Uint8Array.from(s, (c) => c.charCodeAt(0));
// "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
// (CC BY 2.0 FR), in windows-1250.
const slovak = bytes("Ke\xEF som ju uvidel, zamrelo mi srdce.");

let answer = JSON.parse(examine(slovak, "text", "", "sk", true, true));
assert.equal(answer.encoding, "windows-1250");
assert.equal(answer.source, "detection");
assert.equal(answer.decoded.text, "Keď som ju uvidel, zamrelo mi srdce.");
assert.equal(answer.scores[0].encoding, "ISO-8859-4");
assert.ok(answer.ruled_out.includes("UTF-8"));

answer = JSON.parse(examine(bytes("ok \x81 bad"), "text", "gbk", "", true, true));
assert.equal(answer.source, "charset");
assert.deepEqual(answer.decoded.error, {
  message: "invalid GBK: malformed sequence of 1 byte at offset 3",
  offset: 3,
  length: 1,
});

answer = JSON.parse(examine(bytes('<meta charset="Shift_JIS"><p>\x82\xB1\x82\xF1</p>'), "html", "", "", true, true));
assert.equal(answer.encoding, "Shift_JIS");
assert.equal(answer.source, "declared");
assert.equal(answer.decoded.text, '<meta charset="Shift_JIS"><p>こん</p>');

answer = JSON.parse(examine(slovak, "text", "", "co.jp", true, true));
assert.match(answer.problem, /top-level domain/);

assert.deepEqual(JSON.parse(decode_as(slovak, "ISO-8859-4")), {
  text: "Keī som ju uvidel, zamrelo mi srdce.",
  error: null,
});
const names = JSON.parse(encoding_names());
assert.equal(names.length, 40);
assert.equal(names[0], "UTF-8");
console.log(`${site}: the demo module answers as expected`);
