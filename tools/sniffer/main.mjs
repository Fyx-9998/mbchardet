// Writes prescan_data_test.mbt, the test data for prescan_html:
//
//     npm ci --prefix tools/sniffer
//     node tools/sniffer/main.mjs HTML5LIB_DIR WPT_DIR prescan_data_test.mbt
//
// HTML5LIB_DIR holds tests1.dat and tests2.dat from the encoding directory
// of html5lib-tests, and WPT_DIR the html/syntax/xmldecl directory of
// web-platform-tests, at the commits below; their SHA-256 hashes are checked.
// Download them with the commands in .github/workflows/ci.yml. The third
// file of html5lib-tests, test-yahoo-jp.dat, is left out: its one case is
// the start of a real page, which this project does not copy.
//
// The file holds:
//
// - prescan_conformance: the cases of those suites that test the prescan,
//   with the encoding the suite expects. Of html5lib-tests, the cases of at
//   most 1024 bytes, as html5lib's own prescan test takes; the others
//   expect a declaration found while parsing. Of web-platform-tests, the
//   documents xmldecl-1.html and xmldecl-2.html load, except the copies with
//   8 kB of trailing text, which test how a browser waits for bytes, and the
//   documents with an HTTP header.
// - prescan_seeds: short documents, each with what html-encoding-sniffer
//   7.0.0 finds for every mutation of it (see `mutations`). The seeds are
//   the conformance cases of at most 256 bytes and the hand-written ones in
//   `SEEDS`.
//
// What html-encoding-sniffer finds is its whole sniffing: a byte order mark,
// then the prescan, with no encoding from the transport layer. It is run
// with the two changes in `FIXES`, where it departs from the prescan of the
// HTML Standard; prescan_test.mbt tests both cases against the standard.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

// Where html-encoding-sniffer 7.0.0 departs from the standard: what it
// does, what the standard says, and the edits to its source that follow the
// standard, each [text, replacement].
const FIXES = [
  {
    does: "an end tag ends at the first >, even inside a quoted attribute value",
    should: "a tag that starts with </ and a letter has attributes like a start tag",
    edits: [
      [
        "} else if ((c1 >= 0x41 && c1 <= 0x5A) || (c1 >= 0x61 && c1 <= 0x7A)) {",
        "} else if ((c1 >= 0x41 && c1 <= 0x5A) || (c1 >= 0x61 && c1 <= 0x7A) || " +
          "(c1 === 0x2F && ((c2 >= 0x41 && c2 <= 0x5A) || (c2 >= 0x61 && c2 <= 0x7A)))) {",
      ],
    ],
  },
  {
    does: "a content attribute counts after a charset attribute with a label of no encoding",
    should: "charset is then failure, not null, and a later content attribute does not count",
    edits: [
      ["let charset = null;", "let charset = null; let charsetAttributeSeen = false;"],
      [
        'attrRes.attr.name === "content" && !charset)',
        'attrRes.attr.name === "content" && !charset && !charsetAttributeSeen)',
      ],
      [
        "charset = labelToName(attrRes.attr.value);",
        "charset = labelToName(attrRes.attr.value); charsetAttributeSeen = true;",
      ],
    ],
  },
];

// html-encoding-sniffer as published, and with FIXES applied.
function loadSniffers() {
  const require = createRequire(import.meta.url);
  const path = require.resolve("html-encoding-sniffer");
  const published = require(path);
  let source = readFileSync(path, "utf8");
  for (const [from, to] of FIXES.flatMap((fix) => fix.edits)) {
    if (source.split(from).length !== 2) {
      fail(`html-encoding-sniffer does not contain ${JSON.stringify(from)} exactly once`);
    }
    source = source.replace(from, to);
  }
  const module = { exports: {} };
  new Function("require", "module", "exports", source)(createRequire(path), module, module.exports);
  return [published, module.exports];
}

const [publishedSniffer, htmlEncodingSniffer] = loadSniffers();

const HTML5LIB_COMMIT = "c777c408b61078ea2eb4acefc2535f54dbc8b28a";
const WPT_COMMIT = "cf0642a4d2a851574afd696f566987f84f92849f";
const HTML5LIB_FILES = ["tests1.dat", "tests2.dat"];
// The hash of every file read, in the order read, see `read`.
const INPUTS_SHA256 = "743724f5d95469bb42a1620794374f14020a1bdd658eb3c3d7b3dac963818c5b";

// The bytes a mutation puts in: markup, quotes, every kind of ASCII
// whitespace, vertical tab (which is not), NUL, letters and a non-ASCII byte.
const ALPHABET = Buffer.from("<>/=\"'-!?; \t\n\x0C\r\x0B\x00Aa\xA0", "latin1");

const SEEDS = [
  `<meta charset="utf-8">`,
  `<meta charset='koi8-r'>`,
  `<meta charset=windows-1251>`,
  `<META CHARSET = " ISO-8859-2 " >`,
  `<meta\tcharset\t=\t"euc-jp"\n>`,
  `<meta/charset=macintosh/>`,
  `<meta http-equiv="Content-Type" content="text/html; charset=euc-kr">`,
  `<meta content='text/html;charset="shift_jis"' http-equiv=content-type>`,
  `<meta http-equiv=content-type content="charset=gbk; charset=big5">`,
  `<meta content="charsetcharset = big5" http-equiv="CONTENT-TYPE">`,
  `<meta http-equiv=refresh content="0; url=x" charset=utf-8>`,
  `<meta charset="utf-8" charset="koi8-r">`,
  `<meta charset=utf-16><meta charset=x-user-defined>`,
  `<meta charset=x-user-defined>`,
  `<meta charset=iso-2022-kr>`,
  `<meta charset=bogus><meta charset=utf-8>`,
  `<metax charset=koi8-r><meta charset=koi8-u>`,
  `<!-- <meta charset=koi8-r> --><meta charset=euc-jp>`,
  `<!--><meta charset=gb18030>`,
  `<p title="<meta charset=koi8-r>" class=x><meta charset=big5>`,
  `<a href='x>y'><meta charset=ibm866>`,
  `<!doctype html><?php x ?><meta charset=windows-1253>`,
  `<html><head><title>x</title><meta name=description content="charset=koi8-r"><meta charset=iso-8859-15></head>`,
  `<?xml version="1.0" encoding="windows-1251"?>`,
  `<?xml version='1.0' encoding = 'koi8-r' ?><meta charset=utf-8>`,
  `<?xml encoding="utf-16"?>`,
  `<?xml encoding="x-user-defined"?>`,
  `<\x00?\x00x\x00m\x00l\x00`,
  `\x00<\x00?\x00x\x00m\x00l`,
];

function fail(message) {
  console.error(`main.mjs: ${message}`);
  process.exit(1);
}

const inputsHash = createHash("sha256");

function read(path) {
  const bytes = readFileSync(path);
  inputsHash.update(createHash("sha256").update(bytes).digest());
  return bytes;
}

// The cases of an html5lib-tests encoding file: the bytes after "#data" up
// to the line "#encoding", without the line break before it, and the line
// after it.
function html5libCases(name, bytes) {
  const text = bytes.toString("latin1");
  const cases = [];
  const parts = text.split("#data\n").slice(1);
  parts.forEach((part, i) => {
    const end = part.indexOf("\n#encoding\n");
    if (end === -1) {
      fail(`${name} case ${i + 1} has no #encoding`);
    }
    const expected = part.slice(end + "\n#encoding\n".length).split("\n")[0];
    cases.push([`html5lib-tests ${name} #${i + 1}`, Buffer.from(part.slice(0, end), "latin1"), expected]);
  });
  return cases;
}

// The documents xmldecl-1.html and xmldecl-2.html load, with the encoding
// the div around each frame expects.
function wptCases(dir) {
  const cases = [];
  for (const page of ["xmldecl-1.html", "xmldecl-2.html"]) {
    const html = read(join(dir, page)).toString("utf8");
    let expected = null;
    for (const [, cls, src] of html.matchAll(/<div class="([^"]+)">|<iframe src="support\/([^"]+)">/g)) {
      if (cls !== undefined) {
        expected = cls;
      } else if (src.endsWith(".htm") && !src.endsWith("-trail.htm")) {
        cases.push([`web-platform-tests xmldecl/support/${src}`, read(join(dir, "support", src)), expected]);
      }
    }
  }
  return cases;
}

// What html-encoding-sniffer finds, or null.
function sniff(sniffer, bytes) {
  const found = sniffer(bytes, { defaultEncoding: "none" });
  return found === "none" ? null : found;
}

// Every prefix of `seed`, from the empty one; `seed` without each byte; with
// each byte replaced by each byte of ALPHABET; and with each byte of
// ALPHABET inserted before each byte and at the end. The same order as
// mutation_test.mbt.
function mutations(seed) {
  const out = [];
  for (let n = 0; n <= seed.length; n++) {
    out.push(seed.subarray(0, n));
  }
  for (let i = 0; i < seed.length; i++) {
    out.push(Buffer.concat([seed.subarray(0, i), seed.subarray(i + 1)]));
  }
  for (let i = 0; i < seed.length; i++) {
    for (const b of ALPHABET) {
      const copy = Buffer.from(seed);
      copy[i] = b;
      out.push(copy);
    }
  }
  for (let i = 0; i <= seed.length; i++) {
    for (const b of ALPHABET) {
      out.push(Buffer.concat([seed.subarray(0, i), Buffer.from([b]), seed.subarray(i)]));
    }
  }
  return out;
}

function bytesLiteral(bytes) {
  let out = 'b"';
  for (const b of bytes) {
    out += b >= 0x20 && b < 0x7f && b !== 0x22 && b !== 0x5c
      ? String.fromCharCode(b)
      : `\\x${b.toString(16).toUpperCase().padStart(2, "0")}`;
  }
  return out + '"';
}

function main() {
  if (process.argv.length !== 5) {
    fail("usage: node main.mjs HTML5LIB_DIR WPT_DIR PRESCAN_MBT");
  }
  const [html5libDir, wptDir, outPath] = process.argv.slice(2);
  const conformance = [];
  for (const name of HTML5LIB_FILES) {
    for (const [id, bytes, expected] of html5libCases(name, read(join(html5libDir, name)))) {
      if (bytes.length <= 1024) {
        conformance.push([id, bytes, expected]);
      }
    }
  }
  conformance.push(...wptCases(wptDir));
  const hash = inputsHash.digest("hex");
  if (hash !== INPUTS_SHA256) {
    fail(`the input files are not those of html5lib-tests ${HTML5LIB_COMMIT} and web-platform-tests ${WPT_COMMIT} (${hash})`);
  }

  // The names in the order of their first answer, "a" for the first.
  const names = [];
  const letter = (name) => {
    if (name === null) {
      return "-";
    }
    if (!names.includes(name)) {
      names.push(name);
    }
    const i = names.indexOf(name);
    return String.fromCharCode(i < 26 ? 0x61 + i : 0x41 + i - 26);
  };

  let disagreements = 0;
  const lines = [];
  for (const [id, bytes, expected] of conformance) {
    const canonical = htmlEncodingSniffer(Buffer.alloc(0), { transportLayerEncodingLabel: expected });
    const found = htmlEncodingSniffer(bytes);
    if (found !== canonical) {
      disagreements++;
      console.error(`html-encoding-sniffer finds ${found} for ${id}, which expects ${canonical}`);
    }
    lines.push(`  ("${id}", ${bytesLiteral(bytes)}, "${canonical}"),`);
  }

  const seeds = conformance.map(([, bytes]) => bytes).filter((bytes) => bytes.length <= 256);
  seeds.push(...SEEDS.map((seed) => Buffer.from(seed, "latin1")));
  const seen = new Set();
  const seedLines = [];
  let count = 0;
  let fixed = 0;
  for (const seed of seeds) {
    const key = seed.toString("latin1");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    // The answers, run-length encoded: each letter followed by how many
    // mutations in a row give it.
    let answers = "";
    let previous = null;
    let run = 0;
    for (const mutation of mutations(seed)) {
      const found = sniff(htmlEncodingSniffer, mutation);
      if (found !== sniff(publishedSniffer, mutation)) {
        fixed++;
      }
      const a = letter(found);
      count++;
      if (a === previous) {
        run++;
      } else {
        if (previous !== null) {
          answers += previous + run;
        }
        previous = a;
        run = 1;
      }
    }
    answers += previous + run;
    seedLines.push(`  (${bytesLiteral(seed)}, "${answers}"),`);
  }

  const out = [
    "// Generated by tools/sniffer from html-encoding-sniffer 7.0.0, with the",
    `// fixes described there, which change ${fixed} of the ${count} answers.`,
    "// Do not edit.",
    `// prescan_conformance holds cases of html5lib-tests (${HTML5LIB_COMMIT}),`,
    "// MIT License, and of web-platform-tests",
    `// (${WPT_COMMIT}), BSD 3-Clause License. See NOTICE.`,
    "",
    "///|",
    "/// (case, input, the encoding the test suite expects).",
    "let prescan_conformance : Array[(String, Bytes, String)] = [",
    ...lines,
    "]",
    "",
    "///|",
    "/// The bytes `prescan_mutations` puts in.",
    `let prescan_alphabet : Bytes = ${bytesLiteral(ALPHABET)}`,
    "",
    "///|",
    "/// The encodings in prescan_seeds, \"a\" for the first.",
    "let prescan_names : Array[String] = [",
    ...names.map((name) => `  "${name}",`),
    "]",
    "",
    "///|",
    "/// (seed, what html-encoding-sniffer finds for each of its mutations:",
    "/// letters of prescan_names, \"-\" for no encoding, each followed by how",
    "/// many mutations in a row give it).",
    "let prescan_seeds : Array[(Bytes, String)] = [",
    ...seedLines,
    "]",
    "",
  ];
  writeFileSync(outPath, out.join("\n"));
  console.error(`${conformance.length} conformance cases, ${seedLines.length} seeds, ${count} mutations (${fixed} answers fixed), ${disagreements} disagreements with the suites`);
}

main();
