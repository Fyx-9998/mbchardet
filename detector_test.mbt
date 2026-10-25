///|
/// The single-byte encodings `Detector` scores.
fn single_byte_encodings() -> Array[@mbchardet.Encoding] {
  let multi_byte = [
    @mbchardet.Utf8,
    @mbchardet.Gbk,
    @mbchardet.Big5,
    @mbchardet.ShiftJis,
    @mbchardet.EucJp,
    @mbchardet.Iso2022Jp,
    @mbchardet.EucKr,
  ]
  @mbchardet.Detector::encodings().filter(e => !multi_byte.contains(e))
}

///|
fn best_single_byte(detector : @mbchardet.Detector) -> @mbchardet.Encoding? {
  let mut best = None
  let mut best_score = 0L
  for encoding in single_byte_encodings() {
    if detector.score(encoding) is Some(score) &&
      (best is None || score > best_score) {
      best = Some(encoding)
      best_score = score
    }
  }
  best
}

///|
test "a new detector" {
  let detector = @mbchardet.Detector::new()
  assert_eq(single_byte_encodings().length(), 19)
  assert_eq(detector.score(@mbchardet.Utf8), Some(0))
  assert_eq(detector.score(@mbchardet.Windows1252), Some(0))
  // Encodings for non-Latin scripts need a word of two letters.
  assert_eq(detector.score(@mbchardet.Windows1251), None)
  // UTF-16 is only recognized by its byte order mark.
  assert_eq(detector.score(@mbchardet.Utf16Le), None)
  assert_eq(detector.score(@mbchardet.Utf16Be), None)
  assert_eq(detector.score(@mbchardet.Iso2022Jp), Some(0))
}

///|
test "the encodings a detector scores" {
  let scored = @mbchardet.Detector::encodings()
  assert_eq(scored.length(), 26)
  assert_eq(scored, @mbchardet.Encoding::all().filter(e => scored.contains(e)))
  assert_false(scored.contains(@mbchardet.Utf16Le))
  assert_false(scored.contains(@mbchardet.Gb18030))
  // Input that leaves many encodings possible.
  let detector = @mbchardet.Detector::new()
  detector.feed(b"Zdravo \xE8\xE5\xEB\xE0 svete"[:], last=true) |> ignore
  for encoding in @mbchardet.Encoding::all() {
    if !scored.contains(encoding) {
      assert_eq(detector.score(encoding), None)
    }
  }
  assert_true(scored.iter().any(e => detector.score(e) is Some(_)))
}

///|
test "scores ranks the encodings not ruled out" {
  // "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
  // (CC BY 2.0 FR), in windows-1250.
  let detector = @mbchardet.Detector::new()
  detector.feed(b"Ke\xEF som ju uvidel, zamrelo mi srdce."[:], last=true)
  |> ignore
  // Equal scores keep the order of Detector::encodings().
  assert_eq(detector.scores(), [
    (@mbchardet.Iso8859_4, 18L),
    (@mbchardet.Windows1257, 11L),
    (@mbchardet.Iso8859_13, 11L),
    (@mbchardet.Windows1250, 9L),
    (@mbchardet.Iso8859_2, 9L),
    (@mbchardet.Windows1252, 4L),
    (@mbchardet.Windows1254, 0L),
    (@mbchardet.Windows1258, 0L),
  ])
  // A new detector rules out only the encodings that need a word of two
  // letters, and scores the others 0.
  let new = @mbchardet.Detector::new()
  let possible = @mbchardet.Detector::encodings().filter(e => {
    new.score(e) is Some(_)
  })
  assert_eq(new.scores(), possible.map(e => (e, 0L)))
  assert_true(possible.contains(@mbchardet.Utf8))
  assert_false(possible.contains(@mbchardet.Windows1251))
}

///|
test "scores gives what score gives" {
  let inputs : Array[Bytes] = [
    b"", b"Zdravo \xE8\xE5\xEB\xE0 svete", b"x \x81\x98 y", b"Gr\xC3\xBC\xC3\x9Fe",
    b"\x1B$B$3$s$K$A$O\x1B(B",
  ]
  for input in inputs {
    let detector = @mbchardet.Detector::new()
    detector.feed(input[:], last=true) |> ignore
    let ranked = detector.scores()
    for encoding in @mbchardet.Encoding::all() {
      let listed = ranked
        .filter(entry => entry.0 == encoding)
        .map(entry => entry.1)
      match detector.score(encoding) {
        Some(score) => assert_eq(listed, [score])
        None => assert_eq(listed, [])
      }
    }
  }
}

///|
test "ISO-2022-JP can be ruled out from the start" {
  // こんにちは in ISO-2022-JP
  let data = b"\x1B$B$3$s$K$A$O\x1B(B"
  let allowed = @mbchardet.Detector::new()
  allowed.feed(data[:], last=true) |> ignore
  assert_eq(allowed.score(@mbchardet.Iso2022Jp), Some(0))
  let denied = @mbchardet.Detector::new(allow_iso_2022_jp=false)
  denied.feed(data[:], last=true) |> ignore
  assert_eq(denied.score(@mbchardet.Iso2022Jp), None)
  // The other candidates do not change.
  assert_eq(denied.score(@mbchardet.Utf8), allowed.score(@mbchardet.Utf8))
}

///|
test "feed reports whether non-ASCII has been seen" {
  let detector = @mbchardet.Detector::new()
  assert_false(detector.feed(b"plain "[:]))
  assert_false(detector.feed(b""[:]))
  assert_true(detector.feed(b"caf\xE9 "[:]))
  assert_true(detector.feed(b"again"[:], last=true))
}

///|
test "ASCII-only input scores nothing" {
  let detector = @mbchardet.Detector::new()
  detector.feed(b"Nothing here but ASCII, 123."[:], last=true) |> ignore
  for encoding in single_byte_encodings() {
    assert_true(detector.score(encoding) is (None | Some(0)))
  }
  assert_eq(detector.score(@mbchardet.Utf8), Some(0))
}

///|
test "bytes an encoding does not use rule it out" {
  let detector = @mbchardet.Detector::new()
  // 0x81 is unused in windows-1252, 0x98 in windows-1251.
  detector.feed(b"x \x81\x98 y"[:], last=true) |> ignore
  assert_eq(detector.score(@mbchardet.Windows1252), None)
  assert_eq(detector.score(@mbchardet.Windows1251), None)
  // Not UTF-8 either: 0x81 cannot start a character.
  assert_eq(detector.score(@mbchardet.Utf8), None)
}

///|
test "UTF-8 that the end of the stream truncates is ruled out" {
  let open = @mbchardet.Detector::new()
  open.feed(b"Gr\xC3\xBC\xC3"[:]) |> ignore
  assert_eq(open.score(@mbchardet.Utf8), Some(0))
  let closed = @mbchardet.Detector::new()
  closed.feed(b"Gr\xC3\xBC\xC3"[:], last=true) |> ignore
  assert_eq(closed.score(@mbchardet.Utf8), None)
}

///|
test "real text scores highest in its own encoding" {
  // "Надеюсь, вы не слишком много пьёте.", Tatoeba sentence 4792710
  // (CC BY 2.0 FR, in tools/corpus.tsv), in windows-1251 and in KOI8-U.
  let windows_1251 = b"\xCD\xE0\xE4\xE5\xFE\xF1\xFC, \xE2\xFB \xED\xE5 \xF1\xEB\xE8\xF8\xEA\xEE\xEC \xEC\xED\xEE\xE3\xEE \xEF\xFC\xB8\xF2\xE5."
  let koi8_u = b"\xEE\xC1\xC4\xC5\xC0\xD3\xD8, \xD7\xD9 \xCE\xC5 \xD3\xCC\xC9\xDB\xCB\xCF\xCD \xCD\xCE\xCF\xC7\xCF \xD0\xD8\xA3\xD4\xC5."
  let cases = [
    (windows_1251, @mbchardet.Windows1251),
    (koi8_u, @mbchardet.Koi8U),
  ]
  for case in cases {
    let (input, expected) = case
    let detector = @mbchardet.Detector::new()
    detector.feed(input[:], last=true) |> ignore
    assert_eq(best_single_byte(detector), Some(expected))
  }
}

///|
test "how the stream is split does not matter here" {
  let input = b"Il a pr\xE9f\xE9r\xE9 rester \xE0 la maison, o\xF9 il fait chaud."
  let whole = @mbchardet.Detector::new()
  whole.feed(input[:], last=true) |> ignore
  for size in [1, 4, 9] {
    let split = @mbchardet.Detector::new()
    let mut start = 0
    while input.length() - start > size {
      split.feed(input[start:start + size]) |> ignore
      start += size
    }
    split.feed(input[start:], last=true) |> ignore
    for encoding in @mbchardet.Encoding::all() {
      assert_eq(split.score(encoding), whole.score(encoding))
    }
  }
}

///|
test "panic on feeding after the last chunk" {
  let detector = @mbchardet.Detector::new()
  detector.feed(b"done"[:], last=true) |> ignore
  detector.feed(b"more"[:]) |> ignore
}

///|
test "the guess for ASCII depends on whether UTF-8 is allowed" {
  let detector = @mbchardet.Detector::new()
  detector.feed(b"Plain ASCII."[:], last=true) |> ignore
  assert_eq(detector.guess(), @mbchardet.Utf8)
  assert_eq(detector.guess(tld="ru"), @mbchardet.Utf8)
  // Without UTF-8, the default encoding of the domain.
  assert_eq(detector.guess(allow_utf8=false), @mbchardet.Windows1252)
  assert_eq(detector.guess(tld="ru", allow_utf8=false), @mbchardet.Windows1251)
  assert_eq(detector.guess(tld="com", allow_utf8=false), @mbchardet.Windows1252)
}

///|
test "ISO-2022-JP is guessed from escape sequences in ASCII" {
  // こんにちは in ISO-2022-JP
  let data = b"\x1B$B$3$s$K$A$O\x1B(B"
  let allowed = @mbchardet.Detector::new()
  allowed.feed(data[:], last=true) |> ignore
  assert_eq(allowed.guess(), @mbchardet.Iso2022Jp)
  assert_eq(allowed.guess(allow_utf8=false), @mbchardet.Iso2022Jp)
  let denied = @mbchardet.Detector::new(allow_iso_2022_jp=false)
  denied.feed(data[:], last=true) |> ignore
  assert_eq(denied.guess(), @mbchardet.Utf8)
}

///|
test "guessing does not end the stream" {
  let detector = @mbchardet.Detector::new()
  detector.feed(b"caf\xC3\xA9 "[:]) |> ignore
  assert_eq(detector.guess(), @mbchardet.Utf8)
  detector.feed(b"cr\xE8me"[:], last=true) |> ignore
  assert_eq(detector.guess(), @mbchardet.Windows1252)
}

///|
test "panic on a TLD in upper case" {
  @mbchardet.Detector::new().guess(tld="JP") |> ignore
}

///|
test "panic on a TLD with a period" {
  @mbchardet.Detector::new().guess(tld="co.jp") |> ignore
}

///|
test "panic on a TLD outside ASCII" {
  @mbchardet.Detector::new().guess(tld="рф") |> ignore
}

///|
test "panic on tld_may_affect_guess with a TLD in upper case" {
  @mbchardet.tld_may_affect_guess("Com") |> ignore
}
