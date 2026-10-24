# mbchardet

Character encoding detection for [MoonBit](https://www.moonbitlang.com):
given bytes whose encoding is unknown, tell which encoding they are in, so
they can be decoded correctly instead of turning into mojibake.

## Status

Early development. The detector, ported from chardetng 1.0.0, scores the
encodings chardetng detects and guesses between them as chardetng does. The
prescan of the HTML Standard finds the encoding a document declares, and
`sniff_html` and `sniff_xml` find the encoding of a whole document in the
order the HTML Standard and XML 1.0 give. `Encoding::decode` turns bytes into
text and refuses, instead of replacing, a byte sequence that is not valid in
the encoding; the command-line tool can write the text in UTF-8.

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
  X 0212, and the ISO-2022-JP escape sequences. `Detector::encodings()`
  lists the 26 encodings the detector scores.
- `prescan_html(bytes)`: the
  [prescan](https://html.spec.whatwg.org/multipage/parsing.html#prescan-a-byte-stream-to-determine-its-encoding)
  of the HTML Standard, which browsers run before they parse a document
  that has no byte order mark and no encoding from the transport layer. It
  finds the encoding that a `<meta charset>` or a
  `<meta http-equiv="Content-Type" content="...">` in the first 1024 bytes
  declares, otherwise one that an XML declaration such as
  `<?xml version="1.0" encoding="windows-1251"?>` at the start declares, and
  UTF-16 when the document starts with `<?x` in UTF-16. It passes the
  encoding cases of html5lib-tests and the XML declaration cases of
  web-platform-tests, and gives the answers of html-encoding-sniffer 7.0.0
  (of the jsdom project) for 471,093 variations of 131 short documents,
  except in two cases where html-encoding-sniffer departs from the standard
  (see [Testing](#testing)).
- `sniff_html(bytes)` and `sniff_xml(bytes)`: the encoding of a whole
  document, with the step that decided (`Source`). `sniff_html` follows the
  [encoding sniffing algorithm](https://html.spec.whatwg.org/multipage/parsing.html#encoding-sniffing-algorithm)
  of the HTML Standard: a byte order mark, then the encoding label from the
  transport layer (`charset`), then the prescan, then the detector's guess.
  `sniff_xml` takes a byte order mark, then `charset`, in the order of
  [RFC 7303](https://www.rfc-editor.org/rfc/rfc7303#section-3.2), then the
  XML declaration as [XML 1.0](https://www.w3.org/TR/2008/REC-xml-20081126/)
  defines it, and UTF-8 otherwise. A test compares how `sniff_xml` reads
  XML declarations with expat, the XML parser of Firefox, on 61,152
  variations of 34 short documents, except where expat accepts version
  numbers that XML 1.0 does not (see [Testing](#testing)).
- `encoding.decode(bytes)`: the text of `bytes` in any of the 40 encodings,
  or a `DecodeError` with the offset and length of the first malformed byte
  sequence. It decodes as the decoders of the Encoding Standard do with the
  error mode "fatal", like `TextDecoder` with `fatal: true`, and removes a
  byte order mark of the encoding. A test compares the text and the errors
  with encoding_rs 0.8.42 in all 40 encodings: on every input of one byte;
  on every input of two bytes in UTF-8, UTF-16BE, UTF-16LE, GBK, Big5,
  Shift_JIS, EUC-JP, ISO-2022-JP and EUC-KR, and after prefixes such as a
  UTF-16 lead surrogate, the start of a four-byte GB18030 sequence or an
  ISO-2022-JP escape sequence; and on 96,850 variations of 88 short texts.
  The single-byte encodings use tables built from the Encoding Standard's
  index files. See [Decoding](#decoding).
- `mbchardet`, a command-line tool (`cmd/main`): for each file, the
  encoding its byte order mark names if it has one, otherwise the
  detector's guess, and which of them decided. `--charset` passes a label
  from the transport layer, and `--html` and `--xml` find the encoding as
  `sniff_html` and `sniff_xml` do. Other options set the top-level domain,
  deny UTF-8 or ISO-2022-JP, and list the scores. `--output` writes a file
  in UTF-8, unless a byte sequence in it is not valid in the encoding found.
  See [Command line](#command-line).
- `Encoding`: the 40 encodings of the Encoding Standard, with `name()`
  giving the canonical name (`"UTF-8"`, `"windows-1251"`, ...) and
  `Encoding::all()`. These names are valid labels for any decoder that
  follows the standard. `Encoding::from_label(label)` finds the encoding a
  label names, as the standard's
  [get an encoding](https://encoding.spec.whatwg.org/#concept-encoding-get)
  does: `"latin1"` names windows-1252 and `"gb2312"` GBK. A test compares it
  with encoding_rs 0.8.42 on the 228 labels of the standard, variations of
  them in case and whitespace, and strings that are no label. The detector
  and `sniff_bom` only report the first 28 encodings, up to `Ibm866`; the
  others only come from labels.

Planned, not implemented yet:

- A browser demo.

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

## Declared encodings

An encoding can also be named: by a label, such as the `charset` of an HTTP
`Content-Type` header, or by a declaration in the document. Labels are
looked up as the Encoding Standard says, ignoring ASCII case and the ASCII
whitespace around them:

```mbt check
///|
test {
  assert_eq(
    @mbchardet.Encoding::from_label(" Latin1 "),
    Some(@mbchardet.Windows1252),
  )
  assert_eq(
    @mbchardet.Encoding::from_label("x-sjis"),
    Some(@mbchardet.ShiftJis),
  )
  assert_eq(@mbchardet.Encoding::from_label("utf-7"), None)
}
```

`prescan_html` finds what the start of an HTML document declares, the way
browsers do before they parse it. It reads the markup as ASCII, so it works
whatever the encoding of the text, and skips declarations inside comments
and inside the attributes of other tags:

```mbt check
///|
test {
  let page = b"<!doctype html><html><head><meta charset=\"gb2312\"><title>"
  assert_eq(@mbchardet.prescan_html(page[:]), Some(@mbchardet.Gbk))
  let old = b"<meta http-equiv=\"Content-Type\" content=\"text/html; charset=Shift_JIS\">"
  assert_eq(@mbchardet.prescan_html(old[:]), Some(@mbchardet.ShiftJis))
  let xhtml = b"<?xml version=\"1.0\" encoding=\"windows-1251\"?>\n<html>"
  assert_eq(@mbchardet.prescan_html(xhtml[:]), Some(@mbchardet.Windows1251))
  let commented = b"<!-- <meta charset=\"utf-8\"> --><p>"
  assert_eq(@mbchardet.prescan_html(commented[:]), None)
}
```

As the standard requires, a `<meta>` that declares UTF-16 gives UTF-8: a
document whose markup reads as ASCII is not in UTF-16. A declaration can
also be wrong; the prescan reports what the document says, not whether its
bytes agree.

## Sniffing documents

`sniff_html` finds the encoding of an HTML document as a browser does,
trying each step of the HTML Standard in turn, and reports the step that
decided. The label from the transport layer, such as the `charset` of an
HTTP `Content-Type` header, overrides what the document declares, and a
byte order mark overrides both:

```mbt check
///|
test {
  let page = b"<meta charset=\"gb2312\"><title>"
  assert_eq(@mbchardet.sniff_html(page[:]), { encoding: Gbk, source: Prescan, })
  assert_eq(@mbchardet.sniff_html(page[:], charset="Shift_JIS"), {
    encoding: ShiftJis,
    source: TransportLayer,
  })
  let marked = b"\xEF\xBB\xBF<meta charset=\"gb2312\">"
  assert_eq(@mbchardet.sniff_html(marked[:], charset="Shift_JIS"), {
    encoding: Utf8,
    source: ByteOrderMark,
  })
}
```

Pass the value of the `charset` parameter, not the whole header: a string
that is no label of the Encoding Standard counts as none. Without a byte
order mark, a label or a declaration, the detector guesses from all of the
bytes, with the options of `Detector`. To decide as a browser does for a
page from the Web, pass `allow_utf8=false` and `allow_iso_2022_jp=false`,
as chardetng's documentation advises:

```mbt check
///|
test {
  // "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
  // (CC BY 2.0 FR), in windows-1250.
  let page = b"<p>Ke\xEF som ju uvidel, zamrelo mi srdce.</p>"
  assert_eq(@mbchardet.sniff_html(page[:], tld="sk"), {
    encoding: Windows1250,
    source: Detection,
  })
  let german = b"<p>Gr\xC3\xBC\xC3\x9Fe</p>" // "Grüße" in UTF-8
  assert_eq(@mbchardet.sniff_html(german[:]).encoding, @mbchardet.Utf8)
  let web = @mbchardet.sniff_html(
    german[:],
    allow_utf8=false,
    allow_iso_2022_jp=false,
  )
  assert_eq(web.encoding, @mbchardet.Windows1252)
}
```

The HTML Standard calls the encoding *certain* when a byte order mark or
the transport layer gave it, and *tentative* otherwise: a parser that
finds a `<meta>` declaring another encoding later in the document may then
start over with that one. `sniff_html` leaves out the steps of the
standard that depend on the browser: an encoding the user chose, the
encoding of the document around a frame, and the one a page had when it
was last visited.

`sniff_xml` does the same for XML. RFC 7303 puts a byte order mark first
and the transport layer second, and XML 1.0 the XML declaration third.
XML is not guessed: without a declaration the encoding is UTF-8. The
declaration has to come at the very start of the document and follow the
grammar of XML 1.0, and its label is looked up in the Encoding Standard,
as for HTML:

```mbt check
///|
test {
  let feed = b"<?xml version=\"1.0\" encoding=\"windows-1251\"?>\n<rss>"
  assert_eq(@mbchardet.sniff_xml(feed[:]), {
    encoding: Windows1251,
    source: XmlDeclaration,
  })
  assert_eq(
    @mbchardet.sniff_xml(feed[:], charset="koi8-r").encoding,
    @mbchardet.Koi8R,
  )
  assert_eq(@mbchardet.sniff_xml(b"<rss>"[:]), {
    encoding: Utf8,
    source: Default,
  })
  // XML 1.0 puts the version first, so this declaration does not count.
  // The prescan of HTML is not as strict.
  let reversed = b"<?xml encoding=\"windows-1251\" version=\"1.0\"?>"
  assert_eq(@mbchardet.sniff_xml(reversed[:]).source, @mbchardet.Default)
  assert_eq(@mbchardet.prescan_html(reversed[:]), Some(@mbchardet.Windows1251))
}
```

As for HTML, a declaration of UTF-16 that reads as ASCII gives UTF-8. A
document that starts with `<?` in UTF-16 without a byte order mark is
UTF-16LE or UTF-16BE, as appendix F of XML 1.0 detects. XML 1.0 also
detects UTF-32 and EBCDIC, which the Encoding Standard does not define;
`sniff_xml` gives such documents UTF-8.

## Decoding

`Encoding::decode` turns bytes into text, and refuses bytes that are not
valid in the encoding instead of replacing them. A decoder that turns each
malformed sequence into U+FFFD loses the bytes it replaces, and the loss
goes unnoticed until someone reads the result; `decode` says where the first
malformed sequence is:

```mbt check
///|
test {
  // A CSV file in GBK, as Excel on Chinese Windows saves it.
  let csv = b"name,city\n\xD5\xC5\xCE\xB0,\xB1\xB1\xBE\xA9\n"
  let gbk = @mbchardet.Gbk
  assert_eq(gbk.decode(csv[:]), Ok("name,city\n张伟,北京\n"))
  // The same file cut inside its last character.
  match gbk.decode(csv[:csv.length() - 2]) {
    Err(error) => {
      assert_eq(error.valid_up_to, 17)
      assert_eq(error.error_len, None)
      assert_eq(
        error.to_string(),
        "invalid GBK: input ends inside a sequence that starts at offset 17",
      )
    }
    Ok(_) => fail("expected an error")
  }
}
```

With the encoding that `sniff_bom`, `sniff_html`, `sniff_xml` or the
detector finds, `decode` gives the text of input whose encoding was not
known. A byte order mark of the encoding is removed, as `TextDecoder`
removes it:

```mbt check
///|
test {
  let page = b"\xEF\xBB\xBF<p>caf\xC3\xA9</p>"
  let sniffed = @mbchardet.sniff_html(page[:])
  assert_eq(sniffed.encoding.decode(page[:]), Ok("<p>café</p>"))
}
```

Valid does not mean right. In a single-byte encoding nearly every byte is
valid, so text decoded with a wrong guess comes out with wrong letters and
no error. The Slovak sentence of [Usage](#usage), which the detector
guesses as ISO-8859-4 without the `sk` hint, decodes in ISO-8859-4 to
"Keī" where windows-1250 gives "Keď":

```mbt check
///|
test {
  let data = b"Ke\xEF som ju uvidel, zamrelo mi srdce."
  assert_eq(
    @mbchardet.Iso8859_4.decode(data[:]),
    Ok("Keī som ju uvidel, zamrelo mi srdce."),
  )
  assert_eq(
    @mbchardet.Windows1250.decode(data[:]),
    Ok("Keď som ju uvidel, zamrelo mi srdce."),
  )
}
```

Where that matters, pass the encoding when it is known, give the detector
the top-level domain, or look at the scores. The replacement encoding,
which the labels of ISO-2022-KR, ISO-2022-CN and HZ-GB-2312 name, decodes
only empty input. mbchardet does not encode text, nor decode with
replacement; [moon_encoding](https://github.com/LL728/moon_encoding)
implements the encoders of the Encoding Standard, and its decoders with
replacement.

## Command line

`cmd/main` is the `mbchardet` command. `moon run cmd/main --` followed by
its arguments runs it, on any backend (`--target native` builds a native
executable). Here `sk.txt` holds the Slovak sentence above in windows-1250,
`zh.txt` Chinese text in GBK, `bom.csv` a CSV file that starts with a
UTF-8 byte order mark, `ascii.txt` plain ASCII, `page.html` a page with
`<meta charset="Shift_JIS">`, `feed.xml` a feed that starts with
`<?xml version="1.0" encoding="windows-1251"?>`, and `bad.txt` the text
`ok`, a space, the byte 81 and ` bad`, which is not valid GBK:

```
$ moon run cmd/main -- sk.txt zh.txt bom.csv ascii.txt
sk.txt: ISO-8859-4
zh.txt: GBK
bom.csv: UTF-8 (byte order mark)
ascii.txt: UTF-8 (ASCII only)
$ moon run cmd/main -- --tld sk sk.txt
sk.txt: windows-1250
$ moon run cmd/main -- --html page.html
page.html: Shift_JIS (declared)
$ moon run cmd/main -- --xml feed.xml
feed.xml: windows-1251 (declared)
$ moon run cmd/main -- --xml --charset koi8-r feed.xml
feed.xml: KOI8-R (--charset)
$ moon run cmd/main -- --tld sk -o sk.utf8.txt sk.txt
sk.txt: windows-1250
sk.utf8.txt: UTF-8 (converted from sk.txt)
$ moon run cmd/main -- --charset gbk -o out.txt bad.txt
bad.txt: GBK (--charset)
bad.txt: error: invalid GBK: malformed sequence of 1 byte at offset 3 (81); out.txt not written
```

Each file gets a line with its encoding, followed by the step that decided
it: `(byte order mark)`, `(--charset)`, `(declared)` when the document
declares it, with `--html` or `--xml`, or `(default)` for XML that does
not. Without a note, the detector guessed; `(ASCII only)` then says that
every byte is ASCII, so that any encoding the guess could be reads the
file the same way, and `(empty)` that the file is empty.

- `--html`: find the encoding as `sniff_html` does: after a byte order
  mark and `--charset`, the encoding that a `<meta>` or an XML declaration
  in the first 1024 bytes declares, otherwise the guess.
- `--xml`: find the encoding as `sniff_xml` does: after a byte order mark
  and `--charset`, the encoding the XML declaration declares, otherwise
  UTF-8. Nothing is guessed, so the options of the detector cannot be
  given with it.
- `--charset LABEL`: the encoding label the files came with, such as the
  `charset` of an HTTP `Content-Type` header. It decides unless a file
  starts with a byte order mark. A string that is no label of the Encoding
  Standard is an error.
- `--tld LABEL`: the top-level domain the files came from, such as `jp`,
  in Punycode if internationalized (`xn--p1ai`); case does not matter.
- `--deny-utf8`: never guess UTF-8. chardetng's documentation asks browsers
  to do this for HTML from the Web.
- `--deny-iso-2022-jp`: never guess ISO-2022-JP.
- `--scores`: also list each encoding's score, highest first, and the
  encodings ruled out. The scores do not include the `--tld` hint.
- `--output FILE` or `-o FILE`: also write the file, which has to be the
  only one, to `FILE` in UTF-8, without a byte order mark, decoded with
  `Encoding::decode` from the encoding found. If a byte sequence in it is
  not valid in that encoding, nothing is written, and the error gives the
  offset and the bytes of the first one. A wrong guess that happens to be
  valid is converted all the same (see [Decoding](#decoding)), so check
  the encoding or pass `--charset`. Not with `--html` or `--xml`: the
  converted document would still declare its old encoding.

Errors go to standard error, or to standard output with wasm-gc, which has
no standard error in MoonBit. A file that cannot be read, cannot be
converted or cannot be written makes the exit status 1, and an invalid
command line makes it 2; unknown options, options that do not go together
and a missing file name also print the help text.

## Testing

`moon test` runs unit tests, tests of the command-line tool, and golden
tests against data that chardetng, encoding_rs, html-encoding-sniffer and
expat themselves produced. The data and the tables are generated, and CI
checks that regenerating them gives the committed files:

- `tools/gen_corpus.py` picks sentences from Tatoeba into `tools/corpus.tsv`.
- `tools/golden` (Rust, with chardetng 1.0.0 and encoding_rs 0.8.42 pinned
  in `Cargo.lock`) encodes each sentence in every encoding that can
  represent it, adds edge cases, and writes chardetng's scores and guesses
  to `golden_data_test.mbt`. It also writes `golden_trace_wbtest.mbt`, hashes of
  how the CJK decoders of encoding_rs answer byte by byte, and
  `golden_labels_test.mbt`, the encoding that encoding_rs finds for each
  label of the Encoding Standard and for variations of them, and
  `decode_data_test.mbt`, hashes of what its decoders give for whole inputs
  in each of the 40 encodings: groups of every input of one or two bytes
  after a prefix, and 88 short seeds, most of them prefixes of corpus
  sentences, with their variations, made as for `tools/sniffer` with 24
  bytes to replace or insert.
- `tools/gen_data.py` writes chardetng's tables from its `src/data.rs` and
  `src/tld.rs` to `detector_data.mbt`.
- `tools/gen_index.py` writes the GB18030, Big5, JIS X 0208, JIS X 0212 and
  EUC-KR tables from the index files of the Encoding Standard to
  `cjk_index_data.mbt` and the tables of its 27 single-byte indexes to
  `single_byte_index_data.mbt`, and `tools/gen_labels.py` its labels from
  `encodings.json` to `label_data.mbt`; their documentation gives the
  pinned downloads.
- `tools/sniffer` (Node.js, with html-encoding-sniffer 7.0.0 pinned in
  `package-lock.json`) writes `prescan_data_test.mbt`: the 74 encoding cases
  of html5lib-tests that are at most 1024 bytes long and the 41 XML
  declaration documents of web-platform-tests, with the encoding each
  suite expects, and what html-encoding-sniffer finds for 471,093
  variations of 131 short documents (every prefix, and each byte deleted,
  replaced by one of 20 bytes, or preceded by one of them). Before using
  html-encoding-sniffer, the tool corrects it in the two cases where it
  departs from the HTML Standard: it ends an end tag such as `</p` at the
  first `>`, even inside a quoted attribute value, and it lets a `content`
  attribute count after a `charset` attribute whose label names no
  encoding. The first correction changes 63 of the answers, the second
  none; `prescan_test.mbt` tests both cases against the standard.
- `tools/gen_xml_data.py` (Python, with the `pyexpat` module of its
  standard library) writes `xml_data_test.mbt`: the encoding that
  `sniff_xml` should find in 61,152 variations of 34 short documents that
  start with an XML declaration or something close to one, varied as for
  `tools/sniffer`, following what expat, the XML parser of Firefox, reads
  in their declarations. expat does not check the version number and
  accepts, for example, `version="2.0"`, which XML 1.0 does not allow; the
  tool counts such a declaration as none, which changes 1,082 of the
  answers. The committed file was made with expat 2.7.1 and is the same
  with expat 2.7.4; CI makes it again with the Python of its runner.

```
python tools/gen_corpus.py CACHE_DIR tools/corpus.tsv
cargo run --release --locked --manifest-path tools/golden/Cargo.toml -- tools/corpus.tsv golden_data_test.mbt golden_trace_wbtest.mbt WHATWG_DIR/encodings.json golden_labels_test.mbt decode_data_test.mbt
python tools/gen_data.py CHARDETNG_SOURCE/src detector_data.mbt
python tools/gen_index.py WHATWG_DIR cjk_index_data.mbt single_byte_index_data.mbt
python tools/gen_labels.py WHATWG_DIR/encodings.json label_data.mbt
npm ci --prefix tools/sniffer
node tools/sniffer/main.mjs HTML5LIB_DIR WPT_DIR prescan_data_test.mbt
python tools/gen_xml_data.py WHATWG_DIR/encodings.json xml_data_test.mbt
moon fmt
```

## Platforms

The library is pure MoonBit with no dependencies. The command-line tool also
uses `moonbitlang/core/argparse` and, to read and write files, the `fs` and
`sys` packages of [moonbitlang/x](https://github.com/moonbitlang/x) 0.5.6
(Apache 2.0); depending on the module downloads moonbitlang/x, which only the
tool builds. CI checks and tests everything on the wasm, wasm-gc, js and native
backends, on Linux, macOS and Windows, and runs the tool on sample files with
each backend.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT), at your option, except for files that hold data
of others: `cjk_index_data.mbt`, `single_byte_index_data.mbt`,
`label_data.mbt` and `golden_labels_test.mbt` hold data of the WHATWG
Encoding Standard under the [BSD 3-Clause License](LICENSE-WHATWG), and
`prescan_data_test.mbt` holds test cases of html5lib-tests under the
[MIT License](LICENSE-HTML5LIB-TESTS) and of web-platform-tests under the
[BSD 3-Clause License](LICENSE-WPT).

The detector is ported from chardetng 1.0.0 (Apache-2.0 OR MIT, copyright
Mozilla Foundation), and its tables come from chardetng's `data.rs`, which is
dedicated to the public domain. The test corpus consists of Tatoeba
sentences under CC BY 2.0 FR. [NOTICE](NOTICE) lists what comes from where.
