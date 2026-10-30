// The unit tests of chardetng 1.0.0 (src/lib.rs), run against Detector.
// Those that are one call of `check` come from chardetng_tests_data_test.mbt,
// which tools/golden writes; the others are ported here by hand, in the
// order of src/lib.rs. chardetng is licensed under the Apache License 2.0
// or the MIT License, see NOTICE.

///|
/// What chardetng's tests guess: a detector that allows ISO-2022-JP unless
/// told otherwise, fed `chunks` in turn with the end marked on the last,
/// guessing without a top-level domain and with UTF-8 denied. Also what the
/// last call of `feed` returned.
fn chardetng_guess(
  chunks : Array[Bytes],
  allow_iso_2022_jp~ : Bool = true,
) -> (@mbchardet.Encoding, Bool) {
  let detector = @mbchardet.Detector::new(allow_iso_2022_jp~)
  let mut seen_non_ascii = false
  for i, chunk in chunks {
    seen_non_ascii = detector.feed(chunk[:], last=i == chunks.length() - 1)
  }
  (detector.guess(allow_utf8=false), seen_non_ascii)
}

///|
test "chardetng's tests that call check" {
  assert_eq(chardetng_checks.length(), 59)
  for case in chardetng_checks {
    let (name, expected, text, bytes) = case
    guard @mbchardet.Encoding::from_label(expected) is Some(encoding) else {
      fail("\{name}: unknown encoding \{expected}")
    }
    // The bytes are the text in that encoding.
    assert_eq(encoding.decode(bytes[:]), Ok(text), msg=name)
    let (guess, _) = chardetng_guess([bytes])
    assert_eq(guess, encoding, msg=name)
  }
}

///|
/// The bytes of a test that calls `check`.
fn checked_bytes(name : String) -> Bytes {
  for case in chardetng_checks {
    if case.0 == name {
      return case.3
    }
  }
  abort("no test \{name} calls check")
}

///|
/// chardetng's other tests: (name, the chunks fed, whether ISO-2022-JP is
/// allowed, the encoding expected). Repeated characters are written as
/// chardetng builds them.
fn chardetng_other_cases() -> Array[
  (String, Array[Bytes], Bool, @mbchardet.Encoding),
] {
  // 日本語 in ISO-2022-JP, as test_no_2022 encodes it.
  let nihongo = checked_bytes("test_2022")
  let big5 = b"\xA4\x40" // 一
  let euc_kr = b"\xC5\xD7\xBD\xBA\xC6\xAE. " // 테스트.
  let shift_jis = b"\x82\xC9\x82\xD9\x82\xF1\x82\xB2" // にほんご
  let euc_jp = b"\xA4\xCB\xA4\xDB\xA4\xF3\xA4\xB4" // にほんご
  let gbk = b"\xB5\xC4" // 的
  [
    ("test_no_2022", [nihongo], false, Windows1252),
    ("test_i_apostrophe", [b"I\x92"], true, Windows1252),
    (
      "test_streaming_numero_one_by_one",
      [b"n", b".", b"\xBA", b"1"],
      true,
      Windows1252,
    ),
    (
      "test_streaming_numero_two_together",
      [b"n.", b"\xBA", b"1"],
      true,
      Windows1252,
    ),
    (
      "test_streaming_numero_one_by_one_extra_before",
      [b" n", b".", b"\xBA", b"1"],
      true,
      Windows1252,
    ),
    (
      "test_streaming_numero_one_before",
      [b"n", b".\xBA", b"1"],
      true,
      Windows1252,
    ),
    (
      "test_streaming_numero_longer_first_buffer",
      [b"rrn.", b"\xBA", b"1"],
      true,
      Windows1252,
    ),
    ("test_empty", [b""], true, Windows1252),
    // "Don't " with an acute accent for the apostrophe.
    ("test_en_windows1252", [b"Don\xB4t "], true, Windows1252),
    ("test_big5_pua", [big5.repeat(40) + b"\x81\x40\xA4\x40"], true, Big5),
    (
      "test_big5_single_byte_a0",
      [big5.repeat(80) + b"\x81\x40\xA0 "],
      true,
      Big5,
    ),
    (
      "test_big5_single_byte_ff",
      [big5.repeat(80) + b"\x81\x40\xFF "],
      true,
      Big5,
    ),
    ("test_not_big5", [big5.repeat(40) + b"\x81\x40\xA0\xA0"], true, Ibm866),
    ("test_euc_kr_pua", [b"\xC9\xA1\xB0\xA1 " + euc_kr.repeat(40)], true, EucKr),
    (
      "test_euc_kr_pua_bis",
      [b"\xFE\xA1\xB0\xA1 " + euc_kr.repeat(40)],
      true,
      EucKr,
    ),
    ("test_euc_kr_single_byte_ff", [b"\xFF " + euc_kr.repeat(40)], true, EucKr),
    ("test_euc_kr_single_byte_81", [b"\x81 " + euc_kr.repeat(40)], true, EucKr),
    ("test_euc_kr_single_byte_84", [b"\x84 " + euc_kr.repeat(40)], true, EucKr),
    ("test_not_euc_kr", [b"\xC9\xA0\xB0\xA1 " + euc_kr.repeat(40)], true, Gbk),
    (
      "test_shift_jis_x0213",
      [b"\x87\xE5" + shift_jis.repeat(40)],
      true,
      ShiftJis,
    ),
    (
      "test_shift_jis_single_byte_fd",
      [b"\xFD" + shift_jis.repeat(40)],
      true,
      ShiftJis,
    ),
    ("test_not_shift_jis", [b"\x84\xE0" + shift_jis.repeat(40)], true, Gbk),
    ("test_not_shift_jis_bis", [b"\x87\x7D" + shift_jis.repeat(40)], true, Gbk),
    ("test_euc_jp_x0213", [b"\xAD\xBF" + euc_jp.repeat(80)], true, EucJp),
    (
      "test_euc_jp_x0213_other_plane",
      [b"\x8F\xFE\xF6" + euc_jp.repeat(80)],
      true,
      EucJp,
    ),
    (
      "test_not_euc_jp",
      [b"\x8F\xFE\xF7" + euc_jp.repeat(80)],
      true,
      Windows1252,
    ),
    ("test_not_euc_jp_bis", [b"\xA8\xDF" + euc_jp.repeat(80)], true, Big5),
    ("test_gbk_single_byte_ff", [b"\xFF" + gbk.repeat(80)], true, Gbk),
    ("test_gbk_single_byte_a0", [b"\xA0 " + gbk.repeat(80)], true, Gbk),
    ("test_gbk_single_byte_fe", [b"\xFE " + gbk.repeat(80)], true, Gbk),
    (
      "test_not_gbk_single_byte_fc",
      [b"\xFC " + gbk.repeat(80)],
      true,
      Iso8859_5,
    ),
  ]
}

///|
test "chardetng's other tests" {
  let cases = chardetng_other_cases()
  // Every test of chardetng is ported, once.
  assert_eq(cases.map(case => case.0), chardetng_other_tests)
  assert_eq(chardetng_checks.length() + cases.length(), 90)
  for case in cases {
    let (name, chunks, allow_iso_2022_jp, expected) = case
    let (guess, seen_non_ascii) = chardetng_guess(chunks, allow_iso_2022_jp~)
    assert_eq(guess, expected, msg=name)
    if name == "test_empty" {
      assert_false(seen_non_ascii)
    }
  }
}
