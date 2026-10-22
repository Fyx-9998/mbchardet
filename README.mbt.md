# mbchardet

Character encoding detection for [MoonBit](https://www.moonbitlang.com):
given bytes whose encoding is unknown, tell which encoding they are in, so
they can be decoded correctly instead of turning into mojibake.

## Status

Early development. The detector scores UTF-8, GBK, Big5 and the single-byte
encodings but does not make a final guess yet, and the Japanese and Korean
encodings are not covered.

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
- `Detector`: chardetng's detector, ported from
  [chardetng](https://github.com/hsivonen/chardetng) 1.0.0, the detector
  Firefox uses for unlabeled legacy content. Feed it the input in chunks with
  `feed`; `score(encoding)` then tells how plausible the input is in that
  encoding, or that it is ruled out. It scores UTF-8, GBK (which covers
  GB18030's four-byte sequences), Big5 (with HKSCS) and 19 single-byte
  encodings: windows-874, windows-1250 to windows-1258, ISO-8859-2, -4, -5,
  -6, -7, -8 and -13, KOI8-U and IBM866. The scores are chardetng's: a golden
  test compares them with chardetng 1.0.0 on 262 inputs, each fed whole and
  in chunks of 1, 2, 3 and 7 bytes. The GBK and Big5 candidates use their
  own decoders, built from the Encoding Standard's index tables; a second
  test compares them with the decoders of encoding_rs 0.8.42, which
  chardetng uses, on every one- and two-byte input and every four-byte
  GB18030 sequence in the BMP.
- `Encoding`: the encodings mbchardet reports, with `name()` giving the
  canonical name from the Encoding Standard (`"UTF-8"`, `"windows-1251"`,
  ...) and `Encoding::all()`. These names are valid labels for any decoder
  that follows the standard.

Planned, not implemented yet:

- chardetng's candidates for Shift_JIS, EUC-JP, EUC-KR and ISO-2022-JP, and
  its final guess, which compares all candidates and can take a top-level
  domain as a hint. Until then, picking the highest score by hand, as in the
  examples below, only chooses between the encodings above. Valid UTF-8 is
  not proof that UTF-8 was meant; that decision belongs to the guess.
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

The detector scores each encoding; higher is more plausible. Here a Russian
sentence in windows-1251 is not valid UTF-8, and windows-1251 scores highest
of the encodings scored:

```mbt check
///|
test {
  // "Надеюсь, вы не слишком много пьёте.", Tatoeba sentence 4792710
  // (CC BY 2.0 FR), in windows-1251.
  let data = b"\xCD\xE0\xE4\xE5\xFE\xF1\xFC, \xE2\xFB \xED\xE5 \xF1\xEB\xE8\xF8\xEA\xEE\xEC \xEC\xED\xEE\xE3\xEE \xEF\xFC\xB8\xF2\xE5."
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  assert_eq(detector.score(@mbchardet.Utf8), None)
  let mut best = None
  for encoding in @mbchardet.Encoding::all() {
    match (detector.score(encoding), best) {
      (Some(score), None) => best = Some((encoding, score))
      (Some(score), Some((_, best_score))) if score > best_score =>
        best = Some((encoding, score))
      _ => ()
    }
  }
  assert_eq(best.map(b => b.0), Some(@mbchardet.Windows1251))
}
```

Simplified Chinese in GBK, the encoding of many Chinese files written on
Windows: the same bytes are possible but implausible Big5, and not UTF-8.
The scores are the ones chardetng gives:

```mbt check
///|
test {
  // "我们将11月28日作为Tatoeba日来庆祝，因为土耳其语、世界语和希腊语是在那天被
  // 加上去的。", Tatoeba sentence 845121 (CC BY 2.0 FR), in GBK.
  let data = b"\xCE\xD2\xC3\xC7\xBD\xAB11\xD4\xC228\xC8\xD5\xD7\xF7\xCE\xAATatoeba\xC8\xD5\xC0\xB4\xC7\xEC\xD7\xA3\xA3\xAC\xD2\xF2\xCE\xAA\xCD\xC1\xB6\xFA\xC6\xE4\xD3\xEF\xA1\xA2\xCA\xC0\xBD\xE7\xD3\xEF\xBA\xCD\xCF\xA3\xC0\xB0\xD3\xEF\xCA\xC7\xD4\xDA\xC4\xC7\xCC\xEC\xB1\xBB\xBC\xD3\xC9\xCF\xC8\xA5\xB5\xC4\xA1\xA3"
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  assert_eq(detector.score(@mbchardet.Utf8), None)
  assert_eq(detector.score(@mbchardet.Gbk), Some(1413))
  assert_eq(detector.score(@mbchardet.Big5), Some(-445))
}
```

Input can arrive in chunks: call `feed` for each and set `last=true` on the
final one, which may be empty. The end of the input counts as a space after
the last word, so leave `last` unset to score a prefix of a longer stream.

## Testing

`moon test` runs unit tests and golden tests against data that chardetng
and encoding_rs themselves produced. The data and the tables are generated,
and CI checks that regenerating them gives the committed files:

- `tools/gen_corpus.py` picks sentences from Tatoeba into `tools/corpus.tsv`.
- `tools/golden` (Rust, with chardetng 1.0.0 and encoding_rs 0.8.42 pinned
  in `Cargo.lock`) encodes each sentence in every encoding that can
  represent it, adds edge cases, and writes chardetng's scores to
  `golden_data_test.mbt`. It also writes `golden_trace_wbtest.mbt`, hashes of
  how the GBK and Big5 decoders of encoding_rs answer byte by byte.
- `tools/gen_data.py` writes chardetng's tables from its `src/data.rs` to
  `detector_data.mbt`.
- `tools/gen_index.py` writes the GB18030 and Big5 tables from the index
  files of the Encoding Standard to `cjk_index_data.mbt`; its documentation
  gives the pinned download.

```
python tools/gen_corpus.py CACHE_DIR tools/corpus.tsv
cargo run --release --locked --manifest-path tools/golden/Cargo.toml -- tools/corpus.tsv golden_data_test.mbt golden_trace_wbtest.mbt
python tools/gen_data.py CHARDETNG_SOURCE/src/data.rs detector_data.mbt
python tools/gen_index.py WHATWG_INDEX_DIR cjk_index_data.mbt
moon fmt
```

## Platforms

mbchardet is pure MoonBit with no dependencies. CI checks and tests it on the
wasm, wasm-gc, js and native backends, on Linux, macOS and Windows.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT), at your option, except `cjk_index_data.mbt`,
which holds data of the WHATWG Encoding Standard under the
[BSD 3-Clause License](LICENSE-WHATWG).

The detector is ported from chardetng 1.0.0 (Apache-2.0 OR MIT, copyright
Mozilla Foundation), and its tables come from chardetng's `data.rs`, which is
dedicated to the public domain. The test corpus consists of Tatoeba
sentences under CC BY 2.0 FR. [NOTICE](NOTICE) lists what comes from where.
