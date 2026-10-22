# mbchardet

Character encoding detection for [MoonBit](https://www.moonbitlang.com):
given bytes whose encoding is unknown, tell which encoding they are in, so
they can be decoded correctly instead of turning into mojibake.

## Status

Early development. The building blocks below are implemented; the
statistical detector is not.

Implemented:

- `sniff_bom(bytes)`: the "BOM sniff" step of the
  [WHATWG Encoding Standard](https://encoding.spec.whatwg.org/#bom-sniff).
  It recognizes the byte order marks of UTF-8 (`EF BB BF`), UTF-16BE
  (`FE FF`) and UTF-16LE (`FF FE`) and returns the encoding together with the
  length of the mark.
- `check_utf8(bytes)` and `Utf8Validator`: UTF-8 validation, in one call or
  chunk by chunk, with the rules of the Encoding Standard's
  [UTF-8 decoder](https://encoding.spec.whatwg.org/#utf-8-decoder). The result
  tells pure ASCII apart from UTF-8 with other characters, and an error gives
  the offset and length of the first malformed sequence. Splitting the input
  into chunks never changes the result.
- `Encoding`: the encodings mbchardet reports, with `name()` giving the
  canonical name from the Encoding Standard (`"UTF-8"`, `"UTF-16BE"`,
  `"UTF-16LE"`). These names are valid labels for any decoder that follows the
  standard.

Planned, not implemented yet:

- Detection of unlabeled legacy encodings (GBK, Big5, Shift_JIS, EUC-JP,
  EUC-KR, ISO-2022-JP, the windows-125x and ISO-8859 families, KOI8-U,
  IBM866), and deciding between them and UTF-8, ported from
  [chardetng](https://github.com/hsivonen/chardetng) 1.0.0 and checked
  against it with golden tests. Valid UTF-8 is not proof that UTF-8 was
  meant; that decision belongs to the detector.
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

UTF-8 validation reports the first error with its position, so a caller can
reject the input with a precise message instead of decoding it lossily:

```mbt check
///|
test {
  // "café au lait" in windows-1252, where é is the single byte E9.
  let data = b"caf\xE9 au lait"
  match @mbchardet.check_utf8(data[:]) {
    Invalid(error) => {
      assert_eq(error.valid_up_to, 3L)
      assert_eq(
        error.to_string(),
        "invalid UTF-8: malformed sequence of 1 byte at offset 3",
      )
    }
    _ => fail("expected invalid UTF-8")
  }
  assert_eq(@mbchardet.check_utf8(b"caf\xC3\xA9"[:]), @mbchardet.Valid)
  assert_eq(@mbchardet.check_utf8(b"cafe"[:]), @mbchardet.AsciiOnly)
}
```

For input that arrives in pieces, feed each piece to a `Utf8Validator`; a
character may be split between pieces:

```mbt check
///|
test {
  let validator = @mbchardet.Utf8Validator::new()
  assert_true(validator.feed(b"\xE4\xB8"[:])) // the first two bytes of 中
  assert_true(validator.feed(b"\xAD\xE6\x96\x87"[:])) // its last byte, then 文
  assert_eq(validator.finish(), @mbchardet.Valid)
}
```

## Platforms

mbchardet is pure MoonBit with no dependencies. CI checks and tests it on the
wasm, wasm-gc, js and native backends, on Linux, macOS and Windows.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT), at your option.

The current code is written from the Encoding Standard; it contains no code
from other projects.
