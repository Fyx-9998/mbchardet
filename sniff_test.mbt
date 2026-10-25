///|
fn html(
  document : Bytes,
  charset? : String,
  tld? : String,
  allow_utf8? : Bool,
  allow_iso_2022_jp? : Bool,
) -> @mbchardet.Sniffed {
  @mbchardet.sniff_html(
    document[:],
    charset?=charset.map(label => label[:]),
    tld?,
    allow_utf8?,
    allow_iso_2022_jp?,
  )
}

///|
fn text(
  data : Bytes,
  charset? : String,
  tld? : String,
  allow_utf8? : Bool,
  allow_iso_2022_jp? : Bool,
) -> @mbchardet.Sniffed {
  @mbchardet.sniff_text(
    data[:],
    charset?=charset.map(label => label[:]),
    tld?,
    allow_utf8?,
    allow_iso_2022_jp?,
  )
}

///|
fn xml(document : Bytes, charset? : String) -> @mbchardet.Sniffed {
  @mbchardet.sniff_xml(document[:], charset?=charset.map(label => label[:]))
}

///|
/// "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
/// (CC BY 2.0 FR), in windows-1250.
let slovak : Bytes = b"<p>Ke\xEF som ju uvidel, zamrelo mi srdce.</p>"

///|
test "sniff_html: a byte order mark comes first" {
  let page = b"\xEF\xBB\xBF<meta charset=\"gbk\">"
  assert_eq(html(page), { encoding: Utf8, source: ByteOrderMark, })
  assert_eq(html(page, charset="Shift_JIS"), {
    encoding: Utf8,
    source: ByteOrderMark,
  })
  assert_eq(html(b"\xFF\xFE<\x00p\x00>\x00"), {
    encoding: Utf16Le,
    source: ByteOrderMark,
  })
  assert_eq(html(b"\xFE\xFF\x00<\x00p\x00>"), {
    encoding: Utf16Be,
    source: ByteOrderMark,
  })
}

///|
test "sniff_html: then the transport layer" {
  let page = b"<meta charset=\"gbk\"><p>"
  assert_eq(html(page, charset="Shift_JIS"), {
    encoding: ShiftJis,
    source: TransportLayer,
  })
  // A label is looked up as the Encoding Standard says.
  assert_eq(html(page, charset=" Latin1 "), {
    encoding: Windows1252,
    source: TransportLayer,
  })
  // Unlike a declaration in the document, the transport layer can give
  // UTF-16, x-user-defined and the replacement encoding.
  assert_eq(html(page, charset="utf-16"), {
    encoding: Utf16Le,
    source: TransportLayer,
  })
  assert_eq(html(page, charset="x-user-defined"), {
    encoding: XUserDefined,
    source: TransportLayer,
  })
  assert_eq(html(page, charset="iso-2022-kr"), {
    encoding: Replacement,
    source: TransportLayer,
  })
  // What is not a label counts as no label, a whole header included.
  for charset in ["", "bogus", "utf-7", "text/html; charset=utf-8"] {
    assert_eq(html(page, charset~), { encoding: Gbk, source: Prescan, })
  }
}

///|
test "sniff_html: then the prescan" {
  assert_eq(html(b"<meta charset=\"windows-1251\">"), {
    encoding: Windows1251,
    source: Prescan,
  })
  assert_eq(
    html(
      b"<meta http-equiv=\"Content-Type\" content=\"text/html; charset=EUC-JP\">",
    ),
    { encoding: EucJp, source: Prescan, },
  )
  assert_eq(html(b"<?xml version=\"1.0\" encoding=\"koi8-r\"?><html>"), {
    encoding: Koi8R,
    source: Prescan,
  })
  assert_eq(html(b"<\x00?\x00x\x00m\x00l\x00"), {
    encoding: Utf16Le,
    source: Prescan,
  })
  // As the prescan requires, a meta declaring UTF-16 gives UTF-8.
  assert_eq(html(b"<meta charset=\"utf-16\">"), {
    encoding: Utf8,
    source: Prescan,
  })
  // The detector does not overrule a declaration.
  assert_eq(html(b"<meta charset=\"utf-8\">" + slovak), {
    encoding: Utf8,
    source: Prescan,
  })
}

///|
test "sniff_html: then the detector" {
  assert_eq(html(slovak), { encoding: Iso8859_4, source: Detection, })
  assert_eq(html(slovak, tld="sk"), {
    encoding: Windows1250,
    source: Detection,
  })
  // Labels that are no label and declarations past 1024 bytes do not count.
  assert_eq(html(slovak, charset="bogus", tld="sk"), {
    encoding: Windows1250,
    source: Detection,
  })
  let late = slovak + b" ".repeat(1024) + b"<meta charset=\"koi8-r\">"
  assert_eq(html(late, tld="sk"), { encoding: Windows1250, source: Detection, })
  let german = b"<p>Gr\xC3\xBC\xC3\x9Fe</p>" // "Grüße" in UTF-8
  assert_eq(html(german), { encoding: Utf8, source: Detection, })
  assert_eq(html(german, allow_utf8=false), {
    encoding: Windows1252,
    source: Detection,
  })
  assert_eq(html(german, tld="jp", allow_utf8=false), {
    encoding: ShiftJis,
    source: Detection,
  })
}

///|
test "sniff_html: the detector sees the whole input" {
  // Not only the first 1024 bytes, which are ASCII here.
  let long = b"<p>".repeat(400) + slovak
  assert_eq(html(long, tld="sk"), { encoding: Windows1250, source: Detection, })
  assert_eq(html(long[:1024].to_owned(), tld="sk"), {
    encoding: Utf8,
    source: Detection,
  })
  // And the input ends the stream, which counts as a space after the last
  // word. "แม่ของฉันเป็นอาจารย์ด้านจิตวิทยา", Tatoeba sentence 7784182 (CC BY
  // 2.0 FR), in windows-874, is guessed right only then.
  let thai = b"\xE1\xC1\xE8\xA2\xCD\xA7\xA9\xD1\xB9\xE0\xBB\xE7\xB9\xCD\xD2\xA8\xD2\xC3\xC2\xEC\xB4\xE9\xD2\xB9\xA8\xD4\xB5\xC7\xD4\xB7\xC2\xD2"
  assert_eq(html(thai), { encoding: Windows874, source: Detection, })
  let unended = @mbchardet.Detector::new()
  unended.feed(thai[:]) |> ignore
  assert_eq(unended.guess(), @mbchardet.Gbk)
}

///|
test "sniff_html: the options of the detector" {
  // こんにちは in ISO-2022-JP
  let jis = b"<p>\x1B$B$3$s$K$A$O\x1B(B</p>"
  assert_eq(html(jis), { encoding: Iso2022Jp, source: Detection, })
  assert_eq(html(jis, allow_iso_2022_jp=false), {
    encoding: Utf8,
    source: Detection,
  })
  assert_eq(html(jis, allow_utf8=false, allow_iso_2022_jp=false), {
    encoding: Windows1252,
    source: Detection,
  })
  // The same guesses as a Detector makes.
  for document in [slovak, jis, b"", b"<p>plain</p>"] {
    for allow_utf8 in [true, false] {
      let detector = @mbchardet.Detector::new()
      detector.feed(document[:], last=true) |> ignore
      assert_eq(html(document, tld="cz", allow_utf8~), {
        encoding: detector.guess(tld="cz", allow_utf8~),
        source: Detection,
      })
    }
  }
}

///|
test "sniff_xml: a byte order mark, then the transport layer" {
  let feed = b"<?xml version=\"1.0\" encoding=\"windows-1251\"?><rss>"
  assert_eq(xml(b"\xEF\xBB\xBF" + feed), {
    encoding: Utf8,
    source: ByteOrderMark,
  })
  assert_eq(xml(b"\xEF\xBB\xBF" + feed, charset="koi8-r"), {
    encoding: Utf8,
    source: ByteOrderMark,
  })
  assert_eq(xml(feed, charset="koi8-r"), {
    encoding: Koi8R,
    source: TransportLayer,
  })
  assert_eq(xml(feed, charset="bogus"), {
    encoding: Windows1251,
    source: XmlDeclaration,
  })
  assert_eq(xml(feed), { encoding: Windows1251, source: XmlDeclaration, })
}

///|
test "sniff_xml: the XML declaration" {
  fn declaring(label : String) -> @mbchardet.Sniffed {
    xml(@utf8.encode("<?xml version=\"1.0\" encoding=\"\{label}\"?><r/>"))
  }

  assert_eq(declaring("Shift_JIS"), {
    encoding: ShiftJis,
    source: XmlDeclaration,
  })
  assert_eq(declaring("UTF-8"), { encoding: Utf8, source: XmlDeclaration, })
  // Labels are those of the Encoding Standard.
  assert_eq(declaring("ISO-8859-1"), {
    encoding: Windows1252,
    source: XmlDeclaration,
  })
  assert_eq(declaring("x-user-defined"), {
    encoding: XUserDefined,
    source: XmlDeclaration,
  })
  assert_eq(declaring("iso-2022-kr"), {
    encoding: Replacement,
    source: XmlDeclaration,
  })
  // A declaration read as ASCII cannot be in UTF-16.
  assert_eq(declaring("UTF-16"), { encoding: Utf8, source: XmlDeclaration, })
  assert_eq(declaring("utf-16be"), { encoding: Utf8, source: XmlDeclaration, })
  // A name that is no label is ignored.
  assert_eq(declaring("UTF-32"), { encoding: Utf8, source: Default, })
  assert_eq(declaring("EBCDIC-US"), { encoding: Utf8, source: Default, })
}

///|
test "sniff_xml: <? in UTF-16" {
  let utf16le = b"<\x00?\x00x\x00m\x00l\x00 \x00v\x00e\x00r\x00"
  assert_eq(xml(utf16le), { encoding: Utf16Le, source: XmlDeclaration, })
  let utf16be = b"\x00<\x00?\x00x\x00m\x00l\x00 \x00v\x00e\x00r"
  assert_eq(xml(utf16be), { encoding: Utf16Be, source: XmlDeclaration, })
  // Appendix F of XML 1.0 looks at the first four bytes only.
  assert_eq(xml(b"<\x00?\x00"), { encoding: Utf16Le, source: XmlDeclaration, })
  assert_eq(xml(b"\x00<\x00?"), { encoding: Utf16Be, source: XmlDeclaration, })
  assert_eq(xml(b"<\x00?"), { encoding: Utf8, source: Default, })
  assert_eq(xml(b"<\x00p\x00"), { encoding: Utf8, source: Default, })
}

///|
test "sniff_xml: UTF-8 by default" {
  let default : @mbchardet.Sniffed = { encoding: Utf8, source: Default, }
  assert_eq(xml(b""), default)
  assert_eq(xml(b"<r>caf\xE9</r>"), default)
  assert_eq(xml(b"<?xml version=\"1.0\"?><r/>"), default)
  // A declaration that does not follow the grammar is no declaration.
  assert_eq(xml(b"<?xml version=\"2.0\" encoding=\"gbk\"?>"), default)
  assert_eq(xml(b"<?xml encoding=\"gbk\"?>"), default)
  assert_eq(xml(b" <?xml version=\"1.0\" encoding=\"gbk\"?>"), default)
  assert_eq(xml(b"<?xml version=\"1.0\" encoding=\"gbk\""), default)
  // The prescan of HTML does not apply.
  assert_eq(xml(b"<html><head><meta charset=\"gbk\"/>"), default)
  // Neither does detection.
  assert_eq(xml(slovak), default)
  // UTF-32 is not in the Encoding Standard. Its little-endian byte order
  // mark starts with that of UTF-16LE.
  assert_eq(xml(b"\x00\x00\xFE\xFF\x00\x00\x00<"), default)
  assert_eq(xml(b"\x00\x00\x00<\x00\x00\x00?"), default)
  assert_eq(xml(b"\xFF\xFE\x00\x00<\x00\x00\x00"), {
    encoding: Utf16Le,
    source: ByteOrderMark,
  })
}

///|
test "sniff_xml: an XHTML document" {
  let page = b"<?xml version=\"1.0\" encoding=\"iso-8859-2\"?>\n<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><meta charset=\"gbk\"/>"
  assert_eq(xml(page), { encoding: Iso8859_2, source: XmlDeclaration, })
  assert_eq(html(page), { encoding: Gbk, source: Prescan, })
}

///|
test "sniff_text: a byte order mark, then the transport layer" {
  let marked = b"\xEF\xBB\xBFname,city\n"
  assert_eq(text(marked), { encoding: Utf8, source: ByteOrderMark, })
  assert_eq(text(marked, charset="Shift_JIS"), {
    encoding: Utf8,
    source: ByteOrderMark,
  })
  assert_eq(text(b"\xFE\xFF\x00a", charset="gbk"), {
    encoding: Utf16Be,
    source: ByteOrderMark,
  })
  assert_eq(text(slovak, charset=" Latin2 "), {
    encoding: Iso8859_2,
    source: TransportLayer,
  })
  assert_eq(text(slovak, charset="utf-16"), {
    encoding: Utf16Le,
    source: TransportLayer,
  })
  // A string that is no label counts as none.
  assert_eq(text(slovak, charset="bogus", tld="sk"), {
    encoding: Windows1250,
    source: Detection,
  })
}

///|
test "sniff_text: then the detector, without reading declarations" {
  assert_eq(text(slovak), { encoding: Iso8859_4, source: Detection, })
  assert_eq(text(slovak, tld="sk"), {
    encoding: Windows1250,
    source: Detection,
  })
  // A <meta> or an XML declaration is only text.
  let page = b"<meta charset=\"koi8-r\">" + slovak
  assert_eq(html(page, tld="sk"), { encoding: Koi8R, source: Prescan, })
  assert_eq(text(page, tld="sk"), { encoding: Windows1250, source: Detection, })
  let feed = b"<?xml version=\"1.0\" encoding=\"koi8-r\"?>" + slovak
  assert_eq(xml(feed), { encoding: Koi8R, source: XmlDeclaration, })
  assert_eq(text(feed, tld="sk"), { encoding: Windows1250, source: Detection, })
}

///|
test "sniff_text: the options of the detector" {
  // こんにちは in ISO-2022-JP
  let jis = b"\x1B$B$3$s$K$A$O\x1B(B"
  assert_eq(text(jis), { encoding: Iso2022Jp, source: Detection, })
  assert_eq(text(jis, allow_iso_2022_jp=false), {
    encoding: Utf8,
    source: Detection,
  })
  assert_eq(text(jis, allow_utf8=false, allow_iso_2022_jp=false), {
    encoding: Windows1252,
    source: Detection,
  })
  // The same guesses as a Detector fed with the whole input makes.
  let german = b"Gr\xC3\xBC\xC3\x9Fe" // "Grüße" in UTF-8
  for data in [slovak, jis, german, b"", b"plain"] {
    for tld in [None, Some("cz"), Some("jp")] {
      for allow_utf8 in [true, false] {
        for allow_iso_2022_jp in [true, false] {
          let detector = @mbchardet.Detector::new(allow_iso_2022_jp~)
          detector.feed(data[:], last=true) |> ignore
          assert_eq(text(data, tld?, allow_utf8~, allow_iso_2022_jp~), {
            encoding: detector.guess(tld?, allow_utf8~),
            source: Detection,
          })
        }
      }
    }
  }
}
