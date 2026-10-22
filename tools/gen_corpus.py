"""Writes the text corpus the golden tests encode, as tools/corpus.tsv.

    python tools/gen_corpus.py CACHE_DIR tools/corpus.tsv

Downloads the per-language sentence exports of Tatoeba (https://tatoeba.org,
CC BY 2.0 FR) for the languages below into CACHE_DIR, unless they are
already there. For each language it picks two texts that the language's
main legacy encoding can represent:

- medium: one sentence of 31 to 80 characters;
- long: sentences of 20 to 120 characters joined with spaces until the text
  has at least 150 characters.

Sentences are taken in the order of SHA-256("<code>:<id>"), so the choice is
deterministic and does not depend on the export's row order; no sentence is
used twice. Each row records the Tatoeba ids of its sentences for
attribution.

Three kinds of rows are derived from a picked text instead of taken as is,
because legacy files were written that way:

- ro: ș and ț (comma below) become ş and ţ (cedilla), which windows-1250 has;
- vi-1258: tone marks become combining characters after the base letter, the
  form windows-1258 can represent;
- he-visual: the characters in reverse order, as Hebrew in visual order
  (ISO-8859-8) is stored.
"""

import bz2
import hashlib
import os
import sys
import unicodedata
import urllib.request

BASE = "https://downloads.tatoeba.org/exports/per_language"

# (row language, Tatoeba code, Python codec that must represent the text)
LANGUAGES = [
    ("en", "eng", "cp1252"),
    ("fr", "fra", "cp1252"),
    ("de", "deu", "cp1252"),
    ("es", "spa", "cp1252"),
    ("pt", "por", "cp1252"),
    ("it", "ita", "cp1252"),
    ("nl", "nld", "cp1252"),
    ("sv", "swe", "cp1252"),
    ("da", "dan", "cp1252"),
    ("nb", "nob", "cp1252"),
    ("ca", "cat", "cp1252"),
    ("fi", "fin", "cp1252"),
    ("is", "isl", "cp1252"),
    ("pl", "pol", "cp1250"),
    ("cs", "ces", "cp1250"),
    ("sk", "slk", "cp1250"),
    ("hu", "hun", "cp1250"),
    ("hr", "hrv", "cp1250"),
    ("sl", "slv", "cp1250"),
    ("ro", "ron", "cp1250"),
    ("ru", "rus", "cp1251"),
    ("uk", "ukr", "cp1251"),
    ("be", "bel", "cp1251"),
    ("bg", "bul", "cp1251"),
    ("mk", "mkd", "cp1251"),
    ("el", "ell", "cp1253"),
    ("tr", "tur", "cp1254"),
    ("he", "heb", "cp1255"),
    ("ar", "ara", "cp1256"),
    ("fa", "pes", "cp1256"),
    ("ur", "urd", "cp1256"),
    ("lt", "lit", "cp1257"),
    ("lv", "lvs", "cp1257"),
    ("et", "est", "cp1257"),
    ("vi", "vie", "cp1258"),
    ("th", "tha", "cp874"),
]

# Combining marks windows-1258 keeps separate from the base letter.
VIETNAMESE_TONES = {"̀", "́", "̃", "̉", "̣"}


def download(cache, code):
    path = os.path.join(cache, f"{code}_sentences.tsv.bz2")
    if not os.path.exists(path):
        url = f"{BASE}/{code}/{code}_sentences.tsv.bz2"
        print(f"downloading {url}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=300) as resp, open(path + ".part", "wb") as f:
            f.write(resp.read())
        os.replace(path + ".part", path)
    return path


def last_modified(code):
    req = urllib.request.Request(f"{BASE}/{code}/{code}_sentences.tsv.bz2", method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.headers["Last-Modified"]


def romanian_cedilla(text):
    return text.translate(str.maketrans("șțȘȚ", "şţŞŢ"))


def vietnamese_1258(text):
    """Each letter keeps its circumflex, breve or horn precomposed and is
    followed by its tone mark as a combining character, so ệ becomes ê and a
    combining dot below."""
    out = []
    for ch in unicodedata.normalize("NFD", text):
        if unicodedata.combining(ch) and out:
            out[-1].append(ch)
        else:
            out.append([ch])
    letters = []
    for base, *marks in out:
        modifiers = "".join(m for m in marks if m not in VIETNAMESE_TONES)
        tones = "".join(m for m in marks if m in VIETNAMESE_TONES)
        letters.append(unicodedata.normalize("NFC", base + modifiers) + tones)
    return "".join(letters)


def encodable(text, codec):
    try:
        text.encode(codec)
        return True
    except UnicodeEncodeError:
        return False


def candidates(path, code, lang, codec):
    rows = []
    with bz2.open(path, "rt", encoding="utf-8", newline="\n") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            sentence_id, text = int(parts[0]), parts[2]
            if "\t" in text or "\r" in text or not text.strip():
                continue
            text = unicodedata.normalize("NFC", text)
            form = romanian_cedilla(text) if lang == "ro" else text
            if lang == "vi":
                form = vietnamese_1258(text)
            if not encodable(form, codec):
                continue
            key = hashlib.sha256(f"{code}:{sentence_id}".encode()).hexdigest()
            rows.append((key, sentence_id, text))
    rows.sort()
    return rows


def pick(rows):
    """One medium sentence and one long text."""
    medium = None
    long_ids, long_parts, length = [], [], 0
    for _, sentence_id, text in rows:
        if medium is None and 31 <= len(text) <= 80:
            medium = ([sentence_id], text)
        elif length < 150 and 20 <= len(text) <= 120:
            long_ids.append(sentence_id)
            long_parts.append(text)
            length += len(text) + 1
        if medium is not None and length >= 150:
            return [medium, (long_ids, " ".join(long_parts))]
    raise SystemExit("not enough sentences")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    cache, out_path = sys.argv[1], sys.argv[2]
    os.makedirs(cache, exist_ok=True)
    out = []
    for lang, code, codec in LANGUAGES:
        rows = candidates(download(cache, code), code, lang, codec)
        if len(rows) < 10:
            sys.exit(f"gen_corpus.py: only {len(rows)} usable {code} sentences")
        for ids, text in pick(rows):
            id_list = ",".join(str(i) for i in ids)
            if lang == "ro":
                out.append(("ro", id_list, romanian_cedilla(text)))
            elif lang == "vi":
                out.append(("vi", id_list, text))
                out.append(("vi-1258", id_list, vietnamese_1258(text)))
            elif lang == "he":
                out.append(("he", id_list, text))
                out.append(("he-visual", id_list, text[::-1]))
            else:
                out.append((lang, id_list, text))
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Sentences from Tatoeba (https://tatoeba.org), CC BY 2.0 FR,\n")
        f.write("# identified by their Tatoeba sentence ids. Written by\n")
        f.write("# tools/gen_corpus.py; see that file for how rows are derived.\n")
        f.write(f"# Exports dated {last_modified('eng')}.\n")
        f.write("# language\tids\ttext\n")
        for row in out:
            f.write("\t".join(row) + "\n")


if __name__ == "__main__":
    main()
