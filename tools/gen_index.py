"""Writes the decoding tables of the WHATWG Encoding Standard as MoonBit files.

    python tools/gen_index.py WHATWG_DIR cjk_index_data.mbt single_byte_index_data.mbt

Reads index-gb18030.txt, index-gb18030-ranges.txt, index-big5.txt,
index-jis0208.txt, index-jis0212.txt and index-euc-kr.txt for the first
output, and the index files of the 27 single-byte encodings for the second
(ISO-8859-8-I uses the index of ISO-8859-8), from WHATWG_DIR. They must be
the files of whatwg/encoding commit
2c3853e461afd718be198772170d024e427aee21 (the "Adopt GB18030-2022" change,
which the decoders of encoding_rs 0.8.42 follow); their SHA-256 hashes are
checked. Download them with

    for f in gb18030 gb18030-ranges big5 jis0208 jis0212 euc-kr ibm866 \
             iso-8859-2 iso-8859-3 iso-8859-4 iso-8859-5 iso-8859-6 iso-8859-7 \
             iso-8859-8 iso-8859-10 iso-8859-13 iso-8859-14 iso-8859-15 \
             iso-8859-16 koi8-r koi8-u macintosh windows-874 windows-1250 \
             windows-1251 windows-1252 windows-1253 windows-1254 windows-1255 \
             windows-1256 windows-1257 windows-1258 x-mac-cyrillic; do
      curl -fsSLO https://raw.githubusercontent.com/whatwg/encoding/2c3853e461afd718be198772170d024e427aee21/index-$f.txt
    done

The first output, for the CJK decoders:

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

The second output has one table for each single-byte encoding, named after
its index file, such as index_windows_1252: the code point of each of the
bytes 0x80 to 0xFF, as two big-endian bytes each, zero where the index has
no entry. All are in the BMP.
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
    "index-ibm866.txt": "1796f4955dbc5c94e3951a940e9250c819580ce5dd1c9ac396ef73a26e938264",
    "index-iso-8859-2.txt": "86a09a772c5ff8631dc47b8838f0b7751dc31d53fd2eb4262f0fc858e638468b",
    "index-iso-8859-3.txt": "d49c03f3e8cab4fbf861b4471ce121beb937dbd56dfd3106b997326c4b97da0d",
    "index-iso-8859-4.txt": "d93b8b6606e1a12ccf28418a629911b497cb7a354c8a740207992059c50917b3",
    "index-iso-8859-5.txt": "b42bf0bb8d49701efbd8c0fb2bc7330985ce84c576ac51efe86aeff6b47aea5d",
    "index-iso-8859-6.txt": "84b979a90c6a4fb2a2dffe37994647cd4836f918550b46d329b0d798f4b84d52",
    "index-iso-8859-7.txt": "fc1d4295d73dfd0dd6e1b2c2ee3de7a52c6e94ddb09358161d02a2adb08a5151",
    "index-iso-8859-8.txt": "25a8f4366e7935f2c5d59f34e59c400683a1df86546776e7d4e527ae7235cc9e",
    "index-iso-8859-10.txt": "6c1863fca2ad99eed23cc77cce075fcd3cac6bd7b50a584d3067456c2180f16e",
    "index-iso-8859-13.txt": "5c5fe48042ef633a88d1aeed72dd3a2e1fb5202b70c5b7696b53e76ac5e56752",
    "index-iso-8859-14.txt": "310ec047fbd33d8c02de309f0bc8562e453e7d873cc2093005a5d954fc8f0032",
    "index-iso-8859-15.txt": "1171d20bd7c98b5755e8802480d2799527a99847531284cd8d860ffda7cde449",
    "index-iso-8859-16.txt": "e7bee177fdf60c5167b7c44351cd25f51caf9780889493c7855c0eb222a31660",
    "index-koi8-r.txt": "482889b92f244a03fd33ceee13a248a5fd479a3d1633019cc3b21910b8824f52",
    "index-koi8-u.txt": "3b8bfcaa2b7fb125e9790cc4964c4c9e51eee2c9c6e2a80ba7dfd8901546a2c6",
    "index-macintosh.txt": "5e2b0aa162f3032cf6c96a119f59f698da80c16d58014080a6bd246d7ade3c38",
    "index-windows-874.txt": "81b42398e8bef2acc004f38ed6ae2c4d162dfdc367e5ddfcb1cb752ac8814a1e",
    "index-windows-1250.txt": "857f28be0681aae376f1671ab388d8e141cff9648a68803b53887bfdf950f464",
    "index-windows-1251.txt": "bf29b6293d8b5f8011804c575b78a3b589a3fd6a4ace29ff788e3445157a13c0",
    "index-windows-1252.txt": "2c5fa192d566f92b8b9e6e116255b1f94016b4ece5b9dacb3b98be70b8c60795",
    "index-windows-1253.txt": "38390cd918ac2c78c47be62bd486598e7d129e0adceb140c8a7f0165ddbbf3f5",
    "index-windows-1254.txt": "88b7acb81b616bec879521d371eee5766b9306eb050b814e4dce9468e0725822",
    "index-windows-1255.txt": "4a3ca10dd8ef4ce06b929f6bf66d7ea8932ab3c06e07162b0f8a9536a692e6ac",
    "index-windows-1256.txt": "a3e9e6fcf4c3eda90275c791d5d7dad08700374ebe67b17cabdfff1e48f984c1",
    "index-windows-1257.txt": "7e56420f3460befff856365b37733f9eabc1342e82be5999ce34c5eb518fddda",
    "index-windows-1258.txt": "2236cdac45f5970629881d09908d13af96965f1c67617160734cbefb54aa3176",
    "index-x-mac-cyrillic.txt": "a01be0035d0cfbb8da0af780eeb6e7c6169ab26d748d03d15ccd4cd969c5b786",
}

# The index files of the single-byte encodings, in the order of the
# Encoding Standard.
SINGLE_BYTE = list(FILES)[6:]

BIG5_FIRST = 942
BIG5_LAST = 19781

HEADER = [
    "// Generated by tools/gen_index.py from the index files of the WHATWG",
    "// Encoding Standard (whatwg/encoding 2c3853e461afd718be198772170d024e427aee21).",
    "// Do not edit. Licensed under the BSD 3-Clause License, see",
    "// LICENSE-WHATWG and NOTICE.",
    "",
]


def fail(message):
    sys.exit(f"gen_index.py: {message}")


def load(directory, name):
    path = os.path.join(directory, name)
    with open(path, "rb") as f:
        data = f.read()
    if hashlib.sha256(data).hexdigest() != FILES[name]:
        fail(f"{name} is not the file of whatwg/encoding 2c3853e")
    rows = []
    # Not splitlines(): each row shows its character, and splitlines() takes
    # U+0085, a character of the ISO-8859 encodings, for a line break.
    for line in data.decode("utf-8").split("\n"):
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
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    directory, out_path, single_byte_path = sys.argv[1:]
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

    out = HEADER + [
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

    out = HEADER[:]
    for name in SINGLE_BYTE:
        rows = load(directory, name)
        if any(p > 127 for p, _ in rows):
            fail(f"{name} has pointers above 127")
        table = bmp_table(name, rows)
        table += [0] * (256 - len(table))
        variable = name[: -len(".txt")].replace("-", "_")
        out += ["///|", f"let {variable} : Bytes = " + bytes_literal(table), ""]
    with open(single_byte_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
