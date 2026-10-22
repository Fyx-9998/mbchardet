///|
/// The single-byte encodings `Detector` scores.
fn single_byte_encodings() -> Array[@mbchardet.Encoding] {
  let multi_byte = [
    @mbchardet.Utf8,
    @mbchardet.Utf16Be,
    @mbchardet.Utf16Le,
    @mbchardet.Gbk,
    @mbchardet.Big5,
    @mbchardet.ShiftJis,
    @mbchardet.EucJp,
    @mbchardet.Iso2022Jp,
    @mbchardet.EucKr,
  ]
  @mbchardet.Encoding::all().filter(e => !multi_byte.contains(e))
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
