"""Writes chardetng's detection tables as a MoonBit file.

    python tools/gen_data.py PATH/TO/chardetng-1.0.0/src/data.rs detector_data.mbt

Reads the byte classification tables, the character-pair score tables and
the SINGLE_BYTE_DATA entries from chardetng's data.rs, and the frequent
Hanzi of the GBK detector (frequent_simplified), and writes them without
changes. The tables of the Japanese and Korean detectors (frequent_kanji,
frequent_hangul) are not written yet.

The script checks the layout of data.rs instead of guessing: every table
must have the length its declaration states, every pair table the length
its class counts imply, and SINGLE_BYTE_DATA must list the encodings in the
order of the *_INDEX constants. Anything else stops the script with a
message, so a changed data.rs cannot produce a silently different file.
"""

import re
import sys

# encoding_rs statics -> mbchardet Encoding constructors.
ENCODINGS = {
    "WINDOWS_1250_INIT": "Windows1250",
    "WINDOWS_1251_INIT": "Windows1251",
    "WINDOWS_1252_INIT": "Windows1252",
    "WINDOWS_1253_INIT": "Windows1253",
    "WINDOWS_1254_INIT": "Windows1254",
    "WINDOWS_1255_INIT": "Windows1255",
    "WINDOWS_1256_INIT": "Windows1256",
    "WINDOWS_1257_INIT": "Windows1257",
    "WINDOWS_1258_INIT": "Windows1258",
    "WINDOWS_874_INIT": "Windows874",
    "ISO_8859_2_INIT": "Iso8859_2",
    "ISO_8859_4_INIT": "Iso8859_4",
    "ISO_8859_5_INIT": "Iso8859_5",
    "ISO_8859_6_INIT": "Iso8859_6",
    "ISO_8859_7_INIT": "Iso8859_7",
    "ISO_8859_8_INIT": "Iso8859_8",
    "ISO_8859_13_INIT": "Iso8859_13",
    "KOI8_U_INIT": "Koi8U",
    "IBM866_INIT": "Ibm866",
}

# u16 tables of the CJK detectors that are written, and those not yet.
CJK_TABLES = ["frequent_simplified"]
LATER_TABLES = {"frequent_kanji", "frequent_hangul"}


def fail(message):
    sys.exit(f"gen_data.py: {message}")


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", text)


def parse(source):
    source = strip_comments(source)

    struct = re.search(r"pub struct DetectorData \{(.*?)\n\}", source, re.S)
    if not struct:
        fail("struct DetectorData not found")
    declared = {}
    for name, kind, size in re.findall(r"(\w+): \[(u8|u16); (\d+)\]", struct.group(1)):
        declared[name] = (kind, int(size))

    body = re.search(
        r"pub static DETECTOR_DATA: DetectorData = DetectorData \{(.*?)\n\};", source, re.S
    )
    if not body:
        fail("static DETECTOR_DATA not found")
    tables = {}
    for name, values in re.findall(r"(\w+): \[(.*?)\]", body.group(1), re.S):
        tables[name] = [int(v, 0) for v in values.replace(",", " ").split()]
    if set(tables) != set(declared):
        fail(f"DETECTOR_DATA fields {sorted(tables)} differ from the declaration")
    for name, values in tables.items():
        kind, size = declared[name]
        if len(values) != size:
            fail(f"table {name} has {len(values)} values, declared {size}")
        limit = 0xFF if kind == "u8" else 0xFFFF
        if any(v < 0 or v > limit for v in values):
            fail(f"table {name} has a value outside {kind}")

    counts = {
        name: int(value)
        for name, value in re.findall(r"const (\w+_(?:NON_)?ASCII): usize = (\d+);", source)
    }

    entries = re.findall(
        r"SingleByteData \{\s*"
        r"encoding: &(\w+),\s*"
        r"lower: &DETECTOR_DATA\.(\w+),\s*"
        r"upper: &DETECTOR_DATA\.(\w+),\s*"
        r"probabilities: &DETECTOR_DATA\.(\w+),\s*"
        r"ascii: (\w+),\s*"
        r"non_ascii: (\w+),\s*\}",
        source,
    )
    declared_count = re.search(r"pub static SINGLE_BYTE_DATA: \[SingleByteData; (\d+)\]", source)
    if not declared_count or int(declared_count.group(1)) != len(entries):
        fail("SINGLE_BYTE_DATA entries could not all be read")

    indexes = re.findall(r"pub const (\w+)_INDEX: usize = (\d+);", source)
    if [int(i) for _, i in indexes] != list(range(len(entries))):
        fail("the *_INDEX constants do not number SINGLE_BYTE_DATA in order")

    records = []
    for (index_name, _), entry in zip(indexes, entries):
        encoding, lower, upper, probabilities, ascii, non_ascii = entry
        if encoding not in ENCODINGS:
            fail(f"unknown encoding {encoding}")
        for table in (lower, upper):
            if declared[table] != ("u8", 128):
                fail(f"classification table {table} is not [u8; 128]")
        if ascii not in counts or non_ascii not in counts:
            fail(f"class counts {ascii}, {non_ascii} not found")
        a, n = counts[ascii], counts[non_ascii]
        if len(tables[probabilities]) != n * (2 * a + n):
            fail(f"pair table {probabilities} does not match {a} ASCII and {n} non-ASCII classes")
        records.append((index_name, ENCODINGS[encoding], lower, upper, probabilities, a, n))
    return tables, records


def bytes_literal(values):
    return 'b"' + "".join(f"\\x{v:02X}" for v in values) + '"'


def render(tables, records):
    used = []
    for record in records:
        for table in record[2:5]:
            if table not in used:
                used.append(table)
    out = [
        "// Generated by tools/gen_data.py from src/data.rs of chardetng 1.0.0.",
        "// Do not edit. chardetng's data.rs is dedicated to the public domain",
        "// (CC0 1.0); see NOTICE.",
        "",
    ]
    for table in used:
        out += ["///|", f"let {table} : Bytes = {bytes_literal(tables[table])}", ""]
    for i, record in enumerate(records):
        out += ["///|", f"const {record[0]}_INDEX : Int = {i}", ""]
    for table in CJK_TABLES:
        values = ", ".join(f"0x{v:04X}" for v in tables[table])
        out += ["///|", f"let {table} : FixedArray[Int] = [{values}]", ""]
    out += ["///|", "let single_byte_data : FixedArray[SingleByteData] = ["]
    for i, (index_name, encoding, lower, upper, probabilities, a, n) in enumerate(records):
        out += [
            "  {",
            f"    id: {index_name}_INDEX,",
            f"    encoding: {encoding},",
            f"    lower: {lower},",
            f"    upper: {upper},",
            f"    probabilities: {probabilities},",
            f"    ascii: {a},",
            f"    non_ascii: {n},",
            "  },",
        ]
    out += ["]", ""]
    return "\n".join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        tables, records = parse(f.read())
    unused = set(tables) - set(CJK_TABLES) - LATER_TABLES - {t for r in records for t in r[2:5]}
    if unused:
        fail(f"tables {sorted(unused)} are neither used nor known CJK tables")
    with open(sys.argv[2], "w", encoding="utf-8", newline="\n") as f:
        f.write(render(tables, records))


if __name__ == "__main__":
    main()
