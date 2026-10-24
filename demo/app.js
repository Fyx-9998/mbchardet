import { examine, decode_as, encoding_names } from "./mbchardet.js";

// Characters of the decoded text shown on the page; the download has all.
const PREVIEW = 20000;
// Bytes shown on each side of a malformed sequence.
const CONTEXT = 12;

// Bytes written as JavaScript strings with one character per byte.
const bytesOf = (s) => Uint8Array.from(s, (c) => c.charCodeAt(0));

const samples = [
  {
    label: "Slovak, windows-1250",
    file: "slovak.txt",
    bytes: "Ke\xEF som ju uvidel, zamrelo mi srdce.",
    note: "A short sentence leaves room for doubt: chardetng guesses ISO-8859-4, " +
      "which decodes without error but gives “Keī”. " +
      "Type sk as the top-level domain to get windows-1250.",
  },
  {
    label: "Russian, windows-1251",
    file: "russian.txt",
    bytes: "\xCD\xE0\xE4\xE5\xFE\xF1\xFC, \xE2\xFB \xED\xE5 \xF1\xEB\xE8\xF8\xEA\xEE\xEC \xEC\xED\xEE\xE3\xEE \xEF\xFC\xB8\xF2\xE5.",
  },
  {
    label: "Chinese, GBK",
    file: "chinese.txt",
    bytes: "\xCE\xD2\xC3\xC7\xBD\xAB11\xD4\xC228\xC8\xD5\xD7\xF7\xCE\xAATatoeba\xC8\xD5\xC0\xB4\xC7\xEC\xD7\xA3\xA3\xAC\xD2\xF2\xCE\xAA\xCD\xC1\xB6\xFA\xC6\xE4\xD3\xEF\xA1\xA2\xCA\xC0\xBD\xE7\xD3\xEF\xBA\xCD\xCF\xA3\xC0\xB0\xD3\xEF\xCA\xC7\xD4\xDA\xC4\xC7\xCC\xEC\xB1\xBB\xBC\xD3\xC9\xCF\xC8\xA5\xB5\xC4\xA1\xA3",
  },
  {
    label: "Japanese, Shift_JIS",
    file: "japanese.txt",
    bytes: "\x82\xBB\x82\xEA\x82\xA9\x82\xE7\x95\x9E\x82\xF0\x92\x85\x82\xC4\x81A\x8Du\x8B`\x97p\x82\xCC\x83\x81\x83\x82\x82\xF0\x8E\xE8\x82\xB3\x82\xB0\x8A\x93\x82\xC9\x8Bl\x82\xDF\x8D\x9E\x82\xDD\x81A\x8AK\x92i\x82\xF0\x8B\xEC\x82\xAF\x89\xBA\x82\xE8\x82\xBD\x81B",
  },
  {
    label: "Japanese, ISO-2022-JP",
    file: "jis.txt",
    bytes: "\x1B$B$3$s$K$A$O\x1B(B",
    note: "Every byte is ASCII; the escape sequences give ISO-2022-JP away.",
  },
  {
    label: "HTML with <meta charset>",
    file: "page.html",
    bytes: "<meta charset=\"Shift_JIS\"><p>\x82\xB1\x82\xF1</p>",
    options: { mode: "html" },
    note: "Read as HTML, the <meta> decides; read as text, the detector guesses.",
  },
  {
    label: "CSV with a byte order mark",
    file: "cities.csv",
    bytes: "\xEF\xBB\xBFname,city\n\xE5\xBC\xA0\xE4\xBC\x9F,\xE5\x8C\x97\xE4\xBA\xAC\n",
  },
  {
    label: "Truncated GBK",
    file: "cut.csv",
    bytes: "name,city\n\xD5\xC5\xCE\xB0,\xB1\xB1\xBE",
    options: { charset: "gbk" },
    note: "A GBK file cut inside its last character, with the charset label gbk: " +
      "decoding refuses it and shows where.",
  },
];

const $ = (id) => document.getElementById(id);
const fileInput = $("file");
const drop = $("drop");
const fileInfo = $("file-info");
const sampleNote = $("sample-note");
const form = $("options");
const charsetInput = $("charset");
const tldInput = $("tld");
const denyUtf8 = $("deny-utf8");
const denyIso2022Jp = $("deny-iso-2022-jp");
const problem = $("problem");
const result = $("result");
const verdict = $("verdict");
const decodeAs = $("decode-as");
const download = $("download");
const decodedBox = $("decoded");
const scoresBox = $("scores-box");
const scoresList = $("scores");
const ruledOut = $("ruled-out");

// The file being shown: its name and bytes, and its text in the encoding
// chosen, when that decodes.
let current = null;
let text = null;

function el(tag, className, content) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}

function mode() {
  return form.elements.mode.value;
}

function size(n) {
  return n === 1 ? "1 byte" : `${n.toLocaleString("en")} bytes`;
}

for (const name of JSON.parse(encoding_names())) {
  decodeAs.append(new Option(name, name));
}

for (const sample of samples) {
  const button = el("button", "", sample.label);
  button.type = "button";
  button.addEventListener("click", () => {
    const options = { mode: "text", charset: "", tld: "", ...sample.options };
    form.elements.mode.value = options.mode;
    charsetInput.value = options.charset;
    tldInput.value = options.tld;
    denyUtf8.checked = false;
    denyIso2022Jp.checked = false;
    sampleNote.textContent = sample.note ?? "";
    open(sample.file, bytesOf(sample.bytes));
  });
  $("samples").append(button);
}

function open(name, bytes) {
  current = { name, bytes };
  fileInfo.textContent = `${name}, ${size(bytes.length)}`;
  run();
}

async function openFile(file) {
  sampleNote.textContent = "";
  fileInfo.textContent = `Reading ${file.name}…`;
  open(file.name, new Uint8Array(await file.arrayBuffer()));
}

fileInput.addEventListener("change", () => {
  if (fileInput.files.length > 0) openFile(fileInput.files[0]);
});
drop.addEventListener("dragover", (event) => {
  event.preventDefault();
  drop.classList.add("over");
});
drop.addEventListener("dragleave", () => drop.classList.remove("over"));
drop.addEventListener("drop", (event) => {
  event.preventDefault();
  drop.classList.remove("over");
  if (event.dataTransfer.files.length > 0) openFile(event.dataTransfer.files[0]);
});
form.addEventListener("input", run);
form.addEventListener("submit", (event) => event.preventDefault());

const sources = {
  bom: "from its byte order mark",
  charset: "from the charset label",
  declared: "declared in the document",
  detection: "guessed by the detector",
  default: "the default for XML without a declaration",
};

function run() {
  if (!current) return;
  const answer = JSON.parse(examine(
    current.bytes,
    mode(),
    charsetInput.value.trim(),
    tldInput.value.trim(),
    !denyUtf8.checked,
    !denyIso2022Jp.checked,
  ));
  problem.textContent = answer.problem ?? "";
  if (answer.problem) {
    result.hidden = true;
    return;
  }
  result.hidden = false;
  renderVerdict(answer);
  renderScores(answer);
  decodeAs.value = answer.encoding;
  renderDecoded(answer.decoded, answer.encoding);
}

function renderVerdict(answer) {
  const head = el("p", "encoding");
  head.append(el("strong", "", answer.encoding), " ", el("span", "source", sources[answer.source]));
  verdict.replaceChildren(head);
  if (answer.source === "detection" && current.bytes.length === 0) {
    verdict.append(el("p", "hint", "The file is empty."));
  } else if (answer.source === "detection" && answer.ascii && answer.encoding !== "ISO-2022-JP") {
    verdict.append(el("p", "hint",
      "Every byte is ASCII, so the encodings the detector could guess read the file the same way."));
  }
}

function renderScores(answer) {
  scoresBox.hidden = answer.scores === null;
  if (answer.scores === null) return;
  scoresList.replaceChildren();
  const best = Math.max(1, ...answer.scores.map((entry) => entry.score));
  for (const entry of answer.scores) {
    const item = el("li");
    const button = el("button", "score");
    button.type = "button";
    button.dataset.encoding = entry.encoding;
    const bar = el("span", "bar");
    bar.style.width = `${(Math.max(0, entry.score) / best) * 100}%`;
    const track = el("span", "track");
    track.append(bar);
    button.append(el("span", "name", entry.encoding), track, el("span", "value", String(entry.score)));
    button.addEventListener("click", () => {
      decodeAs.value = entry.encoding;
      decodeWith(entry.encoding);
    });
    item.append(button);
    scoresList.append(item);
  }
  ruledOut.textContent = answer.ruled_out.length > 0
    ? `Ruled out: ${answer.ruled_out.join(", ")}.`
    : "";
}

decodeAs.addEventListener("change", () => decodeWith(decodeAs.value));

function decodeWith(encoding) {
  renderDecoded(JSON.parse(decode_as(current.bytes, encoding)), encoding);
}

function renderDecoded(decoded, encoding) {
  for (const button of scoresList.querySelectorAll("button.score")) {
    button.classList.toggle("chosen", button.dataset.encoding === encoding);
  }
  decodedBox.replaceChildren();
  text = decoded.text;
  if (text !== null) {
    const shown = text.length > PREVIEW ? text.slice(0, PREVIEW) : text;
    decodedBox.append(el("pre", "text", shown));
    if (text.length > PREVIEW) {
      decodedBox.append(el("p", "hint",
        `Showing the first ${PREVIEW.toLocaleString("en")} of ${text.length.toLocaleString("en")} characters.`));
    }
  } else {
    renderError(decoded.error);
  }
  const textMode = mode() === "text";
  download.disabled = text === null || !textMode;
  download.title = textMode ? "" :
    "Not for HTML or XML: the converted document would still declare its old encoding.";
}

function renderError(error) {
  const box = el("div", "refused");
  box.append(el("p", "", `Refused: ${error.message}.`));
  const bytes = current.bytes;
  const start = Math.max(0, error.offset - CONTEXT);
  const bad = error.length ?? bytes.length - error.offset;
  const end = Math.min(bytes.length, error.offset + bad + CONTEXT);
  const dump = el("p", "hex");
  dump.append(el("span", "offset", `${start}:`));
  for (let i = start; i < end; i++) {
    const hex = bytes[i].toString(16).toUpperCase().padStart(2, "0");
    const inError = i >= error.offset && i < error.offset + bad;
    dump.append(" ", inError ? el("mark", "", hex) : hex);
  }
  box.append(dump);
  box.append(el("p", "hint", error.length === null
    ? "The file ends inside a character, the marked bytes."
    : "The marked bytes are the malformed sequence."));
  decodedBox.append(box);
}

download.addEventListener("click", () => {
  if (text === null) return;
  // A Blob encodes the text in UTF-8, without a byte order mark.
  const url = URL.createObjectURL(new Blob([text], { type: "text/plain;charset=utf-8" }));
  const link = el("a");
  link.href = url;
  const dot = current.name.lastIndexOf(".");
  link.download = dot > 0
    ? `${current.name.slice(0, dot)}.utf8${current.name.slice(dot)}`
    : `${current.name}.utf8`;
  link.click();
  URL.revokeObjectURL(url);
});
