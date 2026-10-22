"""Writes the GB18030, Big5, JIS and EUC-KR decoding tables as a MoonBit file.

    python tools/gen_index.py WHATWG_DIR cjk_index_data.mbt

Reads index-gb18030.txt, index-gb18030-ranges.txt, index-big5.txt,
index-jis0208.txt, index-jis0212.txt and index-euc-kr.txt of the WHATWG
Encoding Standard from WHATWG_DIR. They must be the files of
whatwg/encoding commit 2c3853e461afd718be198772170d024e427aee21 (the
"Adopt GB18030-2022" change, which the decoders of encoding_rs 0.8.42
follow); their SHA-256 hashes are checked. Download them with

    for f in index-gb18030.txt index-gb18030-ranges.txt index-big5.txt              index-jis0208.txt index-jis0212.txt index-euc-kr.txt; do
      curl -fsSLO https://raw.githubusercontent.com/whatwg/encoding/2c3853e461afd718be198772170d024e427aee21/$f
    done

Output:

- gb18030_index: the code point of every two-byte pointer 0 to 23939, as
  two big-endian bytes each. All are in the BMP.
- gb18030_ranges_pointers and gb18030_ranges_code_points: the 206 ranges
  below pointer 39420 for four-byte sequences (the last range, pointer
  189000, is the linear astral range the decoder computes directly).
- big5_index: the low 16 bits of the code point of every pointer 942 to
  19781, zero where the index has no entry, and big5_astral: one bit per
  pointer for code points in plane 2, the only plane above the BMP Big5
  uses.
- jis0208_index, jis0212_index and euc_kr_index: the code point of every
  pointer from 0 to the last one in each index, as two big-endian bytes
  each, zero where the index has no entry. All are in the BMP. Shift_JIS,
  EUC-JP and ISO-2022-JP use the first, EUC-JP also the second, EUC-KR the
  third.
"""

import hashlib
import os
import sys

FILES = {
    "index-gb18030.txt": "746b3c55f1a8ec4b90b451f384437a17fd37cd51cd668456a28071a758d10784",
    "index-gb18030-ranges.txt": "874c6b6f6f74cf7d427ad228d5b41ddd9354fffd92a2259bf429f86e6baa7a1e",
    "index-big5.txt": "08e24270c8e95d998c994c03f907e972480dc01f58743e078654cc466203c8ff",
    "index-jis0208.txt": "341dcde7e8b984e9c7bbf5ed75c8da7c6087d47083a1a2b3ed558bfd5bef9468",
    "index-jis0212.txt": "6ac698a473822b282ff4f4d4f17873b970612ef9bd232e03941854c09b67c7ee",
    "index-euc-kr.txt": "89af20dd867c84cefb710b1790229786cfef2bf11916361a210d81b90381e267",
}

BIG5_FIRST = 942
BIG5_LAST = 19781


def fail(message):
    sys.exit(f"gen_index.py: {message}")


def load(directory, name):
    path = os.path.join(directory, name)
    with open(path, "rb") as f:
        data = f.read()
    if hashlib.sha256(data).hexdigest() != FILES[name]:
        fail(f"{name} is not the file of whatwg/encoding 2c3853e")
    rows = []
    for line in data.decode("utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        fields = line.split("\t")
        rows.append((int(fields[0]), int(fields[1], 16)))
    return rows


def bmp_table(name, rows):
    """Two big-endian bytes per pointer 0 to the last, zero for no entry."""
    pointers = [p for p, _ in rows]
    if len(set(pointers)) != len(pointers):
        fail(f"{name} has duplicate pointers")
    if any(c == 0 or c > 0xFFFF or 0xD800 <= c < 0xE000 for _, c in rows):
        fail(f"{name} maps to U+0000, a surrogate or above the BMP")
    table = [0] * (2 * (max(pointers) + 1))
    for p, c in rows:
        table[2 * p] = c >> 8
        table[2 * p + 1] = c & 0xFF
    return table


def bytes_literal(values):
    """A Bytes expression, split into literals of 4096 bytes joined with +
    because MoonBit limits the length of a line."""
    chunks = []
    for start in range(0, len(values), 4096):
        chunk = values[start : start + 4096]
        chunks.append('b"' + "".join(f"\\x{v:02X}" for v in chunk) + '"')
    return " +\n  ".join(chunks)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    directory, out_path = sys.argv[1], sys.argv[2]
    gb18030 = load(directory, "index-gb18030.txt")
    ranges = load(directory, "index-gb18030-ranges.txt")
    big5 = load(directory, "index-big5.txt")
    jis0208 = bmp_table("index-jis0208", load(directory, "index-jis0208.txt"))
    jis0212 = bmp_table("index-jis0212", load(directory, "index-jis0212.txt"))
    euc_kr = bmp_table("index-euc-kr", load(directory, "index-euc-kr.txt"))

    if [p for p, _ in gb18030] != list(range(23940)):
        fail("index-gb18030 does not cover pointers 0 to 23939 exactly")
    if any(c > 0xFFFF or 0xD800 <= c < 0xE000 for _, c in gb18030):
        fail("index-gb18030 has a code point outside the BMP or a surrogate")
    if ranges[-1] != (189000, 0x10000) or any(p >= 39420 for p, _ in ranges[:-1]):
        fail("index-gb18030-ranges does not end with the astral range")
    if [p for p, _ in ranges] != sorted(p for p, _ in ranges):
        fail("index-gb18030-ranges is not sorted")
    pointers = [p for p, _ in big5]
    if len(set(pointers)) != len(pointers) or min(pointers) < BIG5_FIRST or max(pointers) > BIG5_LAST:
        fail("index-big5 has duplicate pointers or pointers outside 942 to 19781")
    if any(c == 0 or (c > 0xFFFF and c >> 16 != 2) for _, c in big5):
        fail("index-big5 maps to U+0000 or above the BMP outside plane 2")

    gb_bytes = []
    for _, c in gb18030:
        gb_bytes += [c >> 8, c & 0xFF]
    slots = BIG5_LAST - BIG5_FIRST + 1
    big5_low = [0] * (2 * slots)
    big5_astral = [0] * ((slots + 7) // 8)
    for p, c in big5:
        i = p - BIG5_FIRST
        big5_low[2 * i] = (c >> 8) & 0xFF
        big5_low[2 * i + 1] = c & 0xFF
        if c > 0xFFFF:
            big5_astral[i // 8] |= 1 << (i % 8)

    out = [
        "// Generated by tools/gen_index.py from the index files of the WHATWG",
        "// Encoding Standard (whatwg/encoding 2c3853e461afd718be198772170d024e427aee21).",
        "// Do not edit. Licensed under the BSD 3-Clause License, see",
        "// LICENSE-WHATWG and NOTICE.",
        "",
        "///|",
        "let gb18030_index : Bytes = " + bytes_literal(gb_bytes),
        "",
        "///|",
        "let gb18030_ranges_pointers : FixedArray[Int] = ["
        + ", ".join(str(p) for p, _ in ranges[:-1])
        + "]",
        "",
        "///|",
        "let gb18030_ranges_code_points : FixedArray[Int] = ["
        + ", ".join(f"0x{c:04X}" for _, c in ranges[:-1])
        + "]",
        "",
        "///|",
        f"const BIG5_FIRST_POINTER : Int = {BIG5_FIRST}",
        "",
        "///|",
        f"const BIG5_LAST_POINTER : Int = {BIG5_LAST}",
        "",
        "///|",
        "let big5_index : Bytes = " + bytes_literal(big5_low),
        "",
        "///|",
        "let big5_astral : Bytes = " + bytes_literal(big5_astral),
        "",
        "///|",
        "let jis0208_index : Bytes = " + bytes_literal(jis0208),
        "",
        "///|",
        "let jis0212_index : Bytes = " + bytes_literal(jis0212),
        "",
        "///|",
        "let euc_kr_index : Bytes = " + bytes_literal(euc_kr),
        "",
    ]
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
