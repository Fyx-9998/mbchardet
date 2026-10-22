///|
fn defaults() -> Settings {
  {
    files: [],
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
  // Every encoding but UTF-16 is listed once.
  assert_eq(listed.length() + ruled_out.split(", ").count(), 26)
}

///|
test "equal scores keep the order of Encoding::all()" {
  let data = b"plain words"
  let lines = report("a.txt", data, { ..defaults(), scores: true, })
  let detector = @mbchardet.Detector::new()
  detector.feed(data[:], last=true) |> ignore
  let expected = @mbchardet.Encoding::all()
    .filter(e => !(e is (Utf16Be | Utf16Le)) && detector.score(e) is Some(_))
    .map(e => "  \{e.name()}\{" ".repeat(14 - e.name().length())}0")
  // ASCII scores 0 in every encoding it does not rule out.
  assert_true(expected.length() > 1)
  assert_eq(lines[1:1 + expected.length()].to_owned(), expected)
  assert_eq(lines.length(), expected.length() + 2)
}
