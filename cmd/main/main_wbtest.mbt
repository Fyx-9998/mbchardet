///|
fn defaults() -> Settings {
  {
    files: [],
    kind: Text,
    charset: None,
    tld: None,
    allow_utf8: true,
    allow_iso_2022_jp: true,
    scores: false,
  }
}

///|
/// "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
/// (CC BY 2.0 FR), in windows-1250.
let slovak : Bytes = b"Ke\xEF som ju uvidel, zamrelo mi srdce."

///|
test "parse_args with files only" {
  let settings = parse_args(argv=["a.txt", "b.txt"])
  assert_eq(settings.files, ["a.txt", "b.txt"])
  assert_eq(settings.tld, None)
  assert_true(settings.allow_utf8)
  assert_true(settings.allow_iso_2022_jp)
  assert_false(settings.scores)
}

///|
test "parse_args with every option" {
  let settings = parse_args(argv=[
    "--tld", "SK", "--deny-utf8", "--deny-iso-2022-jp", "--scores", "a.txt",
  ])
  assert_eq(settings.files, ["a.txt"])
  // Case does not matter.
  assert_eq(settings.tld, Some("sk"))
  assert_false(settings.allow_utf8)
  assert_false(settings.allow_iso_2022_jp)
  assert_true(settings.scores)
}

///|
test "parse_args rejects a TLD chardetng cannot take" {
  for tld in ["co.jp", "рф", ""] {
    try parse_args(argv=["--tld", tld, "a.txt"]) catch {
      error =>
        assert_true(
          error.to_string().has_prefix("error: --tld takes the last label"),
        )
    } noraise {
      _ => fail("--tld \{tld} was accepted")
    }
  }
}

///|
test "parse_args needs a file" {
  try parse_args(argv=["--scores"]) catch {
    error =>
      assert_true(
        error.to_string().has_prefix("error: 'files' requires at least 1"),
      )
  } noraise {
    _ => fail("no file was accepted")
  }
}

///|
test "a byte order mark decides" {
  assert_eq(report("a.csv", b"\xEF\xBB\xBFname,city", defaults()), [
    "a.csv: UTF-8 (byte order mark)",
  ])
  assert_eq(report("a.txt", b"\xFF\xFEa\x00", defaults()), [
    "a.txt: UTF-16LE (byte order mark)",
  ])
  // Scores are not listed: the detector is not run.
  assert_eq(
    report("a.txt", b"\xFE\xFF\x00a", { ..defaults(), scores: true, }),
    ["a.txt: UTF-16BE (byte order mark)"],
  )
}

///|
test "the guess, with and without options" {
  assert_eq(report("sk.txt", slovak, defaults()), ["sk.txt: ISO-8859-4"])
  assert_eq(report("sk.txt", slovak, { ..defaults(), tld: Some("sk"), }), [
    "sk.txt: windows-1250",
  ])
  let utf8 = b"Gr\xC3\xBC\xC3\x9Fe"
  assert_eq(report("de.txt", utf8, defaults()), ["de.txt: UTF-8"])
  assert_eq(report("de.txt", utf8, { ..defaults(), allow_utf8: false, }), [
    "de.txt: windows-1252",
  ])
}

///|
test "ASCII and empty files are marked" {
  assert_eq(report("a.txt", b"plain\n", defaults()), [
    "a.txt: UTF-8 (ASCII only)",
  ])
  assert_eq(
    report("a.txt", b"plain\n", {
      ..defaults(),
      tld: Some("jp"),
      allow_utf8: false,
    }),
    ["a.txt: Shift_JIS (ASCII only)"],
  )
  assert_eq(report("e.txt", b"", defaults()), ["e.txt: UTF-8 (empty)"])
}

///|
test "ISO-2022-JP is not marked as ASCII" {
  // こんにちは in ISO-2022-JP
  let data = b"\x1B$B$3$s$K$A$O\x1B(B"
  assert_eq(report("j.txt", data, defaults()), ["j.txt: ISO-2022-JP"])
  assert_eq(
    report("j.txt", data, { ..defaults(), allow_iso_2022_jp: false, }),
    ["j.txt: UTF-8 (ASCII only)"],
  )
}

///|
test "scores are listed highest first" {
  let lines = report("sk.txt", slovak, { ..defaults(), scores: true, })
  assert_eq(lines[0], "sk.txt: ISO-8859-4")
  let detector = @mbchardet.Detector::new()
  detector.feed(slovak[:], last=true) |> ignore
  let mut previous = None
  let listed = []
  for line in lines[1:lines.length() - 1] {
    let name = line[2:16].trim_end(chars=" ").to_owned()
    let encoding = @mbchardet.Encoding::all().search_by(e => e.name() == name)
    guard encoding is Some(i) else { fail("unknown encoding in \"\{line}\"") }
    let score = detector.score(@mbchardet.Encoding::all()[i]).unwrap()
    assert_eq(line, "  \{name}\{" ".repeat(14 - name.length())}\{score}")
    if previous is Some(p) {
      assert_true(score <= p)
    }
    previous = Some(score)
    listed.push(name)
  }
  assert_eq(listed[0], "ISO-8859-4")
  let last = lines[lines.length() - 1]
  guard last.strip_prefix("  ruled out: ") is Some(ruled_out) else {
    fail("no list of encodings ruled out")
  }
  // Every encoding the detector scores is listed once.
  assert_eq(
    listed.length() + ruled_out.split(", ").count(),
    @mbchardet.Detector::encodings().length(),
  )
}

///|
test "equal scores keep the order of Encoding::all()" {
  let data = b"plain words"
  let lines = report("a.txt", data, { ..defaults(), scores: true, })
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  let expected = @mbchardet.Encoding::all()
    .filter(e => detector.score(e) is Some(_))
    .map(e => "  \{e.name()}\{" ".repeat(14 - e.name().length())}0")
  // ASCII scores 0 in every encoding it does not rule out.
  assert_true(expected.length() > 1)
  assert_eq(lines[1:1 + expected.length()].to_owned(), expected)
  assert_eq(lines.length(), expected.length() + 2)
}

///|
test "parse_args with --html, --xml and --charset" {
  let settings = parse_args(argv=["--html", "--charset", "Shift_JIS", "a.html"])
  assert_true(settings.kind is Html)
  assert_eq(settings.charset, Some("Shift_JIS"))
  assert_true(
    parse_args(argv=["--xml", "--charset", "gbk", "a.xml"]).kind is Xml,
  )
  assert_true(parse_args(argv=["a.txt"]).kind is Text)
  assert_eq(parse_args(argv=["a.txt"]).charset, None)
}

///|
test "parse_args rejects options that do not go together" {
  // --xml does not guess, so the options of the detector do not apply.
  for
    argv in [
      ["--html", "--xml", "a"],
      ["--xml", "--tld", "jp", "a"],
      ["--xml", "--deny-utf8", "a"],
      ["--xml", "--deny-iso-2022-jp", "a"],
      ["--xml", "--scores", "a"],
    ] {
    try parse_args(argv~) catch {
      error =>
        assert_true(
          error.to_string().has_prefix("error: conflicting arguments: "),
        )
    } noraise {
      _ => fail("\{argv.join(" ")} was accepted")
    }
  }
}

///|
test "parse_args rejects a charset that is no label" {
  for label in ["bogus", "", "text/html; charset=utf-8"] {
    try parse_args(argv=["--charset", label, "a.txt"]) catch {
      error =>
        assert_true(
          error.to_string().has_prefix("error: --charset takes a label"),
        )
    } noraise {
      _ => fail("--charset \{label} was accepted")
    }
  }
}

///|
test "--charset decides unless there is a byte order mark" {
  let settings = { ..defaults(), charset: Some("windows-1250"), }
  assert_eq(report("sk.txt", slovak, settings), [
    "sk.txt: windows-1250 (--charset)",
  ])
  assert_eq(report("a.csv", b"\xEF\xBB\xBFname", settings), [
    "a.csv: UTF-8 (byte order mark)",
  ])
  // Scores are not listed: the detector is not run.
  assert_eq(report("sk.txt", slovak, { ..settings, scores: true, }), [
    "sk.txt: windows-1250 (--charset)",
  ])
}

///|
test "HTML files" {
  let html = { ..defaults(), kind: Html, }
  let declared = b"<meta charset=\"koi8-r\"><p>"
  assert_eq(report("a.html", declared, html), ["a.html: KOI8-R (declared)"])
  assert_eq(report("a.html", declared, { ..html, charset: Some("gbk"), }), [
    "a.html: GBK (--charset)",
  ])
  assert_eq(report("a.html", declared, { ..html, scores: true, }), [
    "a.html: KOI8-R (declared)",
  ])
  // Without --html, a <meta> declares nothing.
  assert_eq(report("a.txt", declared, defaults()), ["a.txt: UTF-8 (ASCII only)"])
  // Without a declaration, the guess, as for any text.
  let page = b"<p>" + slovak + b"</p>"
  assert_eq(report("sk.html", page, html), ["sk.html: ISO-8859-4"])
  assert_eq(report("sk.html", page, { ..html, tld: Some("sk"), }), [
    "sk.html: windows-1250",
  ])
  assert_eq(
    report("sk.html", page, { ..html, scores: true, }),
    report("sk.html", page, { ..defaults(), scores: true, }),
  )
  assert_eq(report("a.html", b"<p>plain</p>", html), [
    "a.html: UTF-8 (ASCII only)",
  ])
  assert_eq(report("e.html", b"", html), ["e.html: UTF-8 (empty)"])
}

///|
test "XML files" {
  let xml = { ..defaults(), kind: Xml, }
  let feed = b"<?xml version=\"1.0\" encoding=\"windows-1251\"?><rss>"
  assert_eq(report("feed.xml", feed, xml), ["feed.xml: windows-1251 (declared)"])
  assert_eq(report("feed.xml", feed, { ..xml, charset: Some("koi8-r"), }), [
    "feed.xml: KOI8-R (--charset)",
  ])
  assert_eq(report("feed.xml", b"\xEF\xBB\xBF" + feed, xml), [
    "feed.xml: UTF-8 (byte order mark)",
  ])
  // Without a declaration, UTF-8, whatever the bytes: XML is not guessed.
  assert_eq(report("sk.xml", slovak, xml), ["sk.xml: UTF-8 (default)"])
  assert_eq(report("e.xml", b"", xml), ["e.xml: UTF-8 (default)"])
}
