# mbchardet

Character encoding detection for [MoonBit](https://www.moonbitlang.com):
given bytes whose encoding is unknown, tell which encoding they are in, so
they can be decoded correctly instead of turning into mojibake.

## Status

Early development. The detector, ported from chardetng 1.0.0, scores the
encodings chardetng detects and guesses between them as chardetng does.

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
  `feed`; `guess()` then returns the most likely encoding, and
  `score(encoding)` tells how plausible the input is in an encoding, or that
  it is ruled out. It considers UTF-8, GBK (which covers
  GB18030's four-byte sequences), Big5 (with HKSCS), Shift_JIS, EUC-JP,
  ISO-2022-JP, EUC-KR (with the code page 949 extensions) and 19 single-byte
  encodings: windows-874, windows-1250 to windows-1258, ISO-8859-2, -4, -5,
  -6, -7, -8 and -13, KOI8-U and IBM866.
  The guess is chardetng's: input that is ASCII apart from ISO-2022-JP
  escape sequences is ISO-2022-JP, valid UTF-8 is UTF-8 unless
  `allow_utf8=false`, and otherwise the highest score wins, with visual
  Hebrew (ISO-8859-8) preferred over logical Hebrew when its punctuation is
  more plausible. `guess(tld="sk")` takes the top-level domain the input
  came from as a hint, and `tld_may_affect_guess(tld)` tells whether a
  domain is one chardetng has expectations for.
  ISO-2022-JP can be ruled out from the start with
  `Detector::new(allow_iso_2022_jp=false)`, as chardetng advises for Web
  content. The scores and guesses are chardetng's: a golden test compares
  them with chardetng 1.0.0 on 396 inputs, each fed whole and in chunks of
  1, 2, 3 and 7 bytes, with guesses for 33 top-level domain labels and for
  none, each with UTF-8 allowed and denied. The CJK candidates use their own
  decoders, built from the Encoding
  Standard's index tables; a second test compares them with the decoders of
  encoding_rs 0.8.42, which chardetng uses, on every one- and two-byte input,
  every four-byte GB18030 sequence in the BMP, every EUC-JP sequence for JIS
  X 0212, and the ISO-2022-JP escape sequences.
- `mbchardet`, a command-line tool (`cmd/main`): for each file, the
  encoding its byte order mark names if it has one, otherwise the
  detector's guess, with options for the top-level domain, for denying
  UTF-8 or ISO-2022-JP, and for listing the scores. See
  [Command line](#command-line).
- `Encoding`: the encodings mbchardet reports, with `name()` giving the
  canonical name from the Encoding Standard (`"UTF-8"`, `"windows-1251"`,
  ...) and `Encoding::all()`. These names are valid labels for any decoder
  that follows the standard.

Planned, not implemented yet:

- The encoding sniffing steps of the
  [HTML Standard](https://html.spec.whatwg.org/multipage/parsing.html#determining-the-character-encoding):
  byte order mark, transport-layer label, `<meta>` prescan.
- Conversion to UTF-8 that refuses input it cannot convert without loss,
  in the library and the command-line tool, and a browser demo.

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

The detector scores each encoding, higher being more plausible, and guesses
from the scores. Here a Russian sentence in windows-1251 is not valid UTF-8,
and the guess is windows-1251:

```mbt check
///|
test {
  // "Надеюсь, вы не слишком много пьёте.", Tatoeba sentence 4792710
  // (CC BY 2.0 FR), in windows-1251.
  let data = b"\xCD\xE0\xE4\xE5\xFE\xF1\xFC, \xE2\xFB \xED\xE5 \xF1\xEB\xE8\xF8\xEA\xEE\xEC \xEC\xED\xEE\xE3\xEE \xEF\xFC\xB8\xF2\xE5."
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  assert_eq(detector.score(@mbchardet.Utf8), None)
  assert_eq(detector.guess(), @mbchardet.Windows1251)
}
```

A short input leaves room for doubt, and the top-level domain of the site it
came from can settle it. chardetng guesses this Slovak sentence in
windows-1250 wrongly without a domain, and correctly with `sk`:

```mbt check
///|
test {
  // "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
  // (CC BY 2.0 FR), in windows-1250.
  let data = b"Ke\xEF som ju uvidel, zamrelo mi srdce."
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  assert_eq(detector.guess(), @mbchardet.Iso8859_4)
  assert_eq(detector.guess(tld="sk"), @mbchardet.Windows1250)
  assert_true(@mbchardet.tld_may_affect_guess("sk"))
  assert_false(@mbchardet.tld_may_affect_guess("com"))
}
```

Valid UTF-8 is guessed as UTF-8 unless `allow_utf8=false`. chardetng's
documentation asks browsers to pass that for HTML not loaded from a file,
unless the user asked for detection, so that pages do not come to depend on
UTF-8 detection. The guess is then the legacy encoding the domain expects:

```mbt check
///|
test {
  let data = b"Gr\xC3\xBC\xC3\x9Fe" // "Grüße" in UTF-8
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  assert_eq(detector.guess(), @mbchardet.Utf8)
  assert_eq(detector.guess(allow_utf8=false), @mbchardet.Windows1252)
  assert_eq(detector.guess(tld="jp", allow_utf8=false), @mbchardet.ShiftJis)
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

A Japanese sentence in Shift_JIS and in EUC-JP: each scores highest in the
encoding it was written in, and the other Japanese encoding is ruled out.

```mbt check
///|
test {
  // "それから服を着て、講義用のメモを手さげ鞄に詰め込み、階段を駆け下りた。",
  // Tatoeba sentence 205905 (CC BY 2.0 FR).
  let shift_jis = b"\x82\xBB\x82\xEA\x82\xA9\x82\xE7\x95\x9E\x82\xF0\x92\x85\x82\xC4\x81A\x8Du\x8B`\x97p\x82\xCC\x83\x81\x83\x82\x82\xF0\x8E\xE8\x82\xB3\x82\xB0\x8A\x93\x82\xC9\x8Bl\x82\xDF\x8D\x9E\x82\xDD\x81A\x8AK\x92i\x82\xF0\x8B\xEC\x82\xAF\x89\xBA\x82\xE8\x82\xBD\x81B"
  let euc_jp = b"\xA4\xBD\xA4\xEC\xA4\xAB\xA4\xE9\xC9\xFE\xA4\xF2\xC3\xE5\xA4\xC6\xA1\xA2\xB9\xD6\xB5\xC1\xCD\xD1\xA4\xCE\xA5\xE1\xA5\xE2\xA4\xF2\xBC\xEA\xA4\xB5\xA4\xB2\xB3\xF3\xA4\xCB\xB5\xCD\xA4\xE1\xB9\xFE\xA4\xDF\xA1\xA2\xB3\xAC\xC3\xCA\xA4\xF2\xB6\xEE\xA4\xB1\xB2\xBC\xA4\xEA\xA4\xBF\xA1\xA3"
  let detector = @mbchardet.Detector::new()
  detector.feed(shift_jis[:], last=true) |> ignore
  assert_eq(detector.score(@mbchardet.ShiftJis), Some(986))
  assert_eq(detector.score(@mbchardet.Gbk), Some(175))
  assert_eq(detector.score(@mbchardet.EucJp), None)
  let detector = @mbchardet.Detector::new()
  detector.feed(euc_jp[:], last=true) |> ignore
  assert_eq(detector.score(@mbchardet.EucJp), Some(1618))
  assert_eq(detector.score(@mbchardet.Big5), Some(1285))
  assert_eq(detector.score(@mbchardet.ShiftJis), Some(-4193))
}
```

Input can arrive in chunks: call `feed` for each and set `last=true` on the
final one, which may be empty. The end of the input counts as a space after
the last word, so leave `last` unset to score a prefix of a longer stream.

## Command line

`cmd/main` is the `mbchardet` command. `moon run cmd/main --` followed by
its arguments runs it, on any backend (`--target native` builds a native
executable). Here `sk.txt` holds the Slovak sentence above in windows-1250,
`zh.txt` Chinese text in GBK, `bom.csv` a CSV file that starts with a
UTF-8 byte order mark, and `ascii.txt` plain ASCII:

```
$ moon run cmd/main -- sk.txt zh.txt bom.csv ascii.txt
sk.txt: ISO-8859-4
zh.txt: GBK
bom.csv: UTF-8 (byte order mark)
ascii.txt: UTF-8 (ASCII only)
$ moon run cmd/main -- --tld sk sk.txt
sk.txt: windows-1250
```

Each file gets a line with its encoding, followed by `(byte order mark)`
when the mark decided, `(ASCII only)` when every byte is ASCII, so that any
encoding the guess could be reads the file the same way, or `(empty)`.

- `--tld LABEL`: the top-level domain the files came from, such as `jp`,
  in Punycode if internationalized (`xn--p1ai`); case does not matter.
- `--deny-utf8`: never guess UTF-8. chardetng's documentation asks browsers
  to do this for HTML from the Web.
- `--deny-iso-2022-jp`: never guess ISO-2022-JP.
- `--scores`: also list each encoding's score, highest first, and the
  encodings ruled out. The scores do not include the `--tld` hint.

Errors go to standard error, or to standard output with wasm-gc, which has
no standard error in MoonBit. A file that cannot be read makes the exit
status 1, and an invalid command line makes it 2; unknown options and a
missing file name also print the help text.

## Testing

`moon test` runs unit tests, tests of the command-line tool, and golden
tests against data that chardetng and encoding_rs themselves produced. The
data and the tables are generated, and CI checks that regenerating them gives
the committed files:

- `tools/gen_corpus.py` picks sentences from Tatoeba into `tools/corpus.tsv`.
- `tools/golden` (Rust, with chardetng 1.0.0 and encoding_rs 0.8.42 pinned
  in `Cargo.lock`) encodes each sentence in every encoding that can
  represent it, adds edge cases, and writes chardetng's scores and guesses
  to `golden_data_test.mbt`. It also writes `golden_trace_wbtest.mbt`, hashes of
  how the CJK decoders of encoding_rs answer byte by byte.
- `tools/gen_data.py` writes chardetng's tables from its `src/data.rs` and
  `src/tld.rs` to `detector_data.mbt`.
- `tools/gen_index.py` writes the GB18030, Big5, JIS X 0208, JIS X 0212 and
  EUC-KR tables from the index files of the Encoding Standard to
  `cjk_index_data.mbt`; its documentation gives the pinned download.

```
python tools/gen_corpus.py CACHE_DIR tools/corpus.tsv
cargo run --release --locked --manifest-path tools/golden/Cargo.toml -- tools/corpus.tsv golden_data_test.mbt golden_trace_wbtest.mbt
python tools/gen_data.py CHARDETNG_SOURCE/src detector_data.mbt
python tools/gen_index.py WHATWG_INDEX_DIR cjk_index_data.mbt
moon fmt
```

## Platforms

The library is pure MoonBit with no dependencies. The command-line tool also
uses `moonbitlang/core/argparse` and, to read files, the `fs` and `sys`
packages of [moonbitlang/x](https://github.com/moonbitlang/x) 0.5.6 (Apache
2.0); depending on the module downloads moonbitlang/x, which only the tool
builds. CI checks and tests everything on the wasm, wasm-gc, js and native
backends, on Linux, macOS and Windows, and runs the tool on sample files with
each backend.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT), at your option, except `cjk_index_data.mbt`,
which holds data of the WHATWG Encoding Standard under the
[BSD 3-Clause License](LICENSE-WHATWG).

The detector is ported from chardetng 1.0.0 (Apache-2.0 OR MIT, copyright
Mozilla Foundation), and its tables come from chardetng's `data.rs`, which is
dedicated to the public domain. The test corpus consists of Tatoeba
sentences under CC BY 2.0 FR. [NOTICE](NOTICE) lists what comes from where.
