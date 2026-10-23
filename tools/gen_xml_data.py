"""Writes what expat finds in XML declarations, to test sniff_xml against.

    python tools/gen_xml_data.py encodings.json xml_data_test.mbt

encodings.json must be the file of whatwg/encoding commit
2c3853e461afd718be198772170d024e427aee21, as for tools/gen_labels.py; its
SHA-256 hash is checked.

The script varies each of the documents in SEEDS: every prefix, from the
empty one; the document without each byte; with each byte replaced by each
byte of ALPHABET; and with each byte of ALPHABET inserted before each byte
and at the end. For each variation it runs expat, the XML parser of Firefox,
through Python's pyexpat module, and writes the answer of sniff_xml without
a charset that follows from what expat finds: if expat reads an XML
declaration with an encoding declaration, the encoding its label names in
the Encoding Standard, with UTF-16BE and UTF-16LE taken as UTF-8; otherwise,
or if the label names none, UTF-8 by default.

expat does not check the version number: it accepts any value made of the
characters A-Z, a-z, 0-9, ".", "_" and "-", such as "2.0", where XML 1.0
requires '1.' followed by digits (production 26, VersionNum). Following
XML 1.0, the script counts such a declaration as no declaration, and the
output says how many answers that changes.

The committed output was made with expat 2.7.1 (Python 3.12.10 on Windows)
and is the same with expat 2.7.4 (Python 3.14 on Ubuntu 26.04). The version
of expat is printed, not written to the output, which CI makes again with
the Python of its runner.
"""

import hashlib
import json
import pyexpat
import re
import sys

ENCODINGS_SHA256 = "078212b3697f60b81225b6671bd9da2604497abff0aa8e96e4d46605c02ac9e7"

# Documents that start with an XML declaration, or with something close to
# one. Each is followed by what XML 1.0 makes of it.
SEEDS = [
    # Well-formed declarations.
    b'<?xml version="1.0"?>',
    b"<?xml version='1.0'?>",
    b'<?xml version="1.0" encoding="UTF-8"?>',
    b"<?xml version='1.0' encoding='windows-1251'?>",
    b'<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>',
    b"<?xml version=\"1.1\" encoding='Shift_JIS' standalone='no' ?>",
    b'<?xml version="1.0" standalone="no"?>',
    b'<?xml\tversion = "1.0"\r\nencoding\t=\t"gb2312"\n?>',
    b'<?xml  version="1.0"  encoding="cp1250"  ?>',
    b'<?xml version="1.10" encoding="euc_kr"?>',
    b'<?xml version="1.0" encoding="a"?>',
    b'<?xml version="1.0" encoding="A.b_c-9"?>',
    # UTF-16 in a declaration read as ASCII, which gives UTF-8.
    b'<?xml version="1.0" encoding="utf-16"?>',
    # Followed by the start of a document.
    b'<?xml version="1.0" encoding="x-mac-cyrillic"?><r/>',
    b'<?xml version="1.0" encoding="latin1"?><?xml-stylesheet href="s.xsl"?><r/>',
    b'<?xml version="1.0" encoding="windows-1252"?>\n<r>caf\xe9</r>',
    b'<?xml version="1.0" encoding="UTF-8" ?>\n<rss version="2.0">',
    b'<?xml version="1.0" encoding="us-ascii"?>\n<!DOCTYPE svg>',
    # No XML declaration.
    b'<?xml-stylesheet href="s.xsl"?>',
    b'<?XML version="1.0" encoding="cp1250"?>',
    b' <?xml version="1.0" encoding="cp1250"?>',
    b"<?xml?>",
    # Declarations XML 1.0 does not allow.
    b'<?xml version="1.0"encoding="koi8-r"?>',
    b'<?xml encoding="koi8-r" version="1.0"?>',
    b'<?xml version="1.0" standalone="yes" encoding="koi8-r"?>',
    b'<?xml version="1.0" encoding="koi8-r" encoding="utf-8"?>',
    b'<?xml version="1.0" encoding="1252"?>',
    b"<?xml version=\"1.0\" encoding=\"utf-8'?>",
    b'<?xml version="1.0" encoding="big5" standalone="maybe"?>',
    b'<?xml version="1." encoding="utf-8"?>',
    b'<?xml version="2.0" encoding="utf-8"?>',
    b'<?xml version="1.0" encoding=""?>',
    b'<?xml version="1.0" encoding="utf-8"? >',
    b'<?xml version="1.0" encoding="utf-8"',
]

# The bytes the variations put in: those of the grammar, white space that
# XML 1.0 does not count as such (form feed, NEL, no-break space), NUL, and
# letters and a digit to change words.
ALPHABET = b"<?>=\"' \t\n\r\x0c\x00-._1aA\x85\xa0"


def fail(message):
    sys.exit(f"gen_xml_data.py: {message}")


def mutations(seed):
    """The variations of `seed`, in the order of `mutations` in
    mutation_test.mbt."""
    out = [seed[:n] for n in range(len(seed) + 1)]
    out += [seed[:i] + seed[i + 1 :] for i in range(len(seed))]
    for i in range(len(seed)):
        for b in ALPHABET:
            out.append(seed[:i] + bytes([b]) + seed[i + 1 :])
    for i in range(len(seed) + 1):
        for b in ALPHABET:
            out.append(seed[:i] + bytes([b]) + seed[i:])
    return out


def expat_declaration(document):
    """(version, encoding) of the XML declaration expat reads at the start
    of `document`, encoding being None without an encoding declaration, or
    None if expat reads no declaration."""
    parser = pyexpat.ParserCreate()
    found = []
    parser.XmlDeclHandler = lambda version, encoding, standalone: found.append(
        (version, encoding)
    )
    try:
        parser.Parse(document, True)
    except (pyexpat.ExpatError, LookupError, ValueError):
        # Errors after the declaration, such as an encoding Python cannot
        # decode, do not matter: expat calls the handler first.
        pass
    if len(found) > 1:
        fail(f"expat reads two declarations in {document!r}")
    return found[0] if found else None


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, "rb") as f:
        data = f.read()
    if hashlib.sha256(data).hexdigest() != ENCODINGS_SHA256:
        fail("encodings.json is not the file of whatwg/encoding 2c3853e")
    names_by_label = {
        label: e["name"]
        for group in json.loads(data)
        for e in group["encodings"]
        for label in e["labels"]
    }
    print(f"{pyexpat.EXPAT_VERSION}, Python {sys.version.split()[0]}", file=sys.stderr)

    # The encodings in the order of their first answer, "a" for the first.
    names = []

    def letter(name):
        if name is None:
            return "-"
        if name not in names:
            names.append(name)
        i = names.index(name)
        return chr(ord("a") + i) if i < 26 else chr(ord("A") + i - 26)

    count = 0
    corrected = 0
    seed_lines = []
    for seed in SEEDS:
        answers = []
        for mutation in mutations(seed):
            if mutation[:2] in (b"\xfe\xff", b"\xff\xfe") or mutation[:3] == b"\xef\xbb\xbf":
                fail(f"{mutation!r} starts with a byte order mark")
            if mutation[:4] in (b"<\x00?\x00", b"\x00<\x00?"):
                fail(f"{mutation!r} starts with <? in UTF-16")
            declaration = expat_declaration(mutation)
            if declaration is not None and not re.fullmatch(r"1\.[0-9]+", declaration[0]):
                declaration = None
                corrected += 1
            name = None
            if declaration is not None and declaration[1] is not None:
                name = names_by_label.get(declaration[1].lower())
                if name in ("UTF-16BE", "UTF-16LE"):
                    name = "UTF-8"
            answers.append(letter(name))
            count += 1
        # Run-length encoded: each letter followed by how many mutations in
        # a row give it.
        runs = ""
        start = 0
        for i in range(1, len(answers) + 1):
            if i == len(answers) or answers[i] != answers[start]:
                runs += answers[start] + str(i - start)
                start = i
        seed_lines.append(f'  ({bytes_literal(seed)}, "{runs}"),')

    out = [
        "// Generated by tools/gen_xml_data.py, which runs expat through Python's",
        "// pyexpat module, with the correction described there, which changes",
        f"// {corrected} of the {count} answers. Do not edit.",
        "",
        "///|",
        "/// The bytes `mutations` puts in.",
        f"let xml_alphabet : Bytes = {bytes_literal(ALPHABET)}",
        "",
        "///|",
        '/// The encodings in xml_seeds, "a" for the first.',
        "let xml_names : Array[String] = [",
        *[f'  "{name}",' for name in names],
        "]",
        "",
        "///|",
        "/// (seed, the encoding the XML declaration names in each of its",
        '/// mutations: letters of xml_names, "-" for none, each followed by how',
        "/// many mutations in a row give it).",
        "let xml_seeds : Array[(Bytes, String)] = [",
        *seed_lines,
        "]",
        "",
    ]
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print(
        f"{len(SEEDS)} seeds, {count} mutations ({corrected} answers corrected)",
        file=sys.stderr,
    )


def bytes_literal(data):
    out = 'b"'
    for b in data:
        if 0x20 <= b < 0x7F and b not in (0x22, 0x5C):
            out += chr(b)
        else:
            out += f"\\x{b:02X}"
    return out + '"'


if __name__ == "__main__":
    main()
