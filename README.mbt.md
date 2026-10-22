# mbchardet

Character encoding detection for [MoonBit](https://www.moonbitlang.com):
given bytes whose encoding is unknown, tell which encoding they are in, so
they can be decoded correctly instead of turning into mojibake.

## Status

Early development. Only the first building block is implemented.

Implemented:

- `sniff_bom(bytes)`: the "BOM sniff" step of the
  [WHATWG Encoding Standard](https://encoding.spec.whatwg.org/#bom-sniff).
  It recognizes the byte order marks of UTF-8 (`EF BB BF`), UTF-16BE
  (`FE FF`) and UTF-16LE (`FF FE`) and returns the encoding together with the
  length of the mark.
- `Encoding`: the encodings mbchardet reports, with `name()` giving the
  canonical name from the Encoding Standard (`"UTF-8"`, `"UTF-16BE"`,
  `"UTF-16LE"`). These names are valid labels for any decoder that follows the
  standard.

Planned, not implemented yet:

- Detection of unlabeled legacy encodings (GBK, Big5, Shift_JIS, EUC-JP,
  EUC-KR, ISO-2022-JP, the windows-125x and ISO-8859 families, KOI8-U,
  IBM866) and of UTF-8 without a mark, ported from
  [chardetng](https://github.com/hsivonen/chardetng) 1.0.0 and checked
  against it with golden tests.
- The encoding sniffing steps of the
  [HTML Standard](https://html.spec.whatwg.org/multipage/parsing.html#determining-the-character-encoding):
  byte order mark, transport-layer label, `<meta>` prescan.
- A command-line tool, and conversion to UTF-8.

## Usage

The module is not published on mooncakes yet; depend on a checkout of this
repository. The package is imported as `@mbchardet`.

```mbt check
///|
test {
  let data = b"\xEF\xBB\xBFname,city\n"
  assert_eq(@mbchardet.sniff_bom(data[:]), Some((@mbchardet.Utf8, 3)))
  // The text starts after the 3-byte mark.
  assert_eq(data[3:].length(), 10)
  // No mark: the encoding has to be detected some other way.
  assert_eq(@mbchardet.sniff_bom(b"name,city\n"[:]), None)
}
```

`sniff_bom` follows the Encoding Standard exactly. One consequence: the
UTF-32LE mark `FF FE 00 00` is reported as UTF-16LE, because the standard
only looks at the first two bytes. mbchardet does not support UTF-32.

## Platforms

mbchardet is pure MoonBit with no dependencies. CI checks and tests it on the
wasm, wasm-gc, js and native backends, on Linux, macOS and Windows.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT), at your option.

The current code is written from the Encoding Standard; it contains no code
from other projects.
