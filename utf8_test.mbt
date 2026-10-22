///|
fn bytes_of(values : Array[Int32]) -> Bytes {
  Bytes::from_array(values.map(v => v.to_byte()))
}

///|
fn invalid(valid_up_to : Int64, error_len : Int32?) -> @mbchardet.Utf8Status {
  @mbchardet.Invalid(@mbchardet.Utf8Error::{ valid_up_to, error_len, })
}

///|
fn check(values : Array[Int32]) -> @mbchardet.Utf8Status {
  @mbchardet.check_utf8(bytes_of(values)[:])
}

///|
/// Feeds `bytes` to a new validator, cut at the given offsets.
fn feed_in_chunks(bytes : Bytes, cuts : Array[Int32]) -> @mbchardet.Utf8Status {
  let validator = @mbchardet.Utf8Validator::new()
  let mut from = 0
  for cut in cuts {
    validator.feed(bytes[from:cut]) |> ignore
    from = cut
  }
  validator.feed(bytes[from:]) |> ignore
  validator.finish()
}

///|
test "ASCII only" {
  assert_eq(@mbchardet.check_utf8(b""[:]), @mbchardet.AsciiOnly)
  assert_eq(@mbchardet.check_utf8(b"plain text\r\n"[:]), @mbchardet.AsciiOnly)
  assert_eq(check([0x00, 0x7F]), @mbchardet.AsciiOnly)
}

///|
test "valid UTF-8" {
  assert_eq(
    @mbchardet.check_utf8(@utf8.encode("naïve 中文 😀")[:]),
    @mbchardet.Valid,
  )
  // The byte order mark is an ordinary character.
  assert_eq(check([0xEF, 0xBB, 0xBF]), @mbchardet.Valid)
  // The first and last character of each length, and the characters on
  // both sides of the surrogate range.
  for
    sequence in [
      [0xC2, 0x80],
      [0xDF, 0xBF],
      [0xE0, 0xA0, 0x80],
      [0xED, 0x9F, 0xBF],
      [0xEE, 0x80, 0x80],
      [0xEF, 0xBF, 0xBF],
      [0xF0, 0x90, 0x80, 0x80],
      [0xF4, 0x8F, 0xBF, 0xBF],
    ] {
    assert_eq(check(sequence), @mbchardet.Valid)
  }
}

///|
test "bytes that cannot start a character" {
  for lead in [0x80, 0xBF, 0xC0, 0xC1, 0xF5, 0xF8, 0xFE, 0xFF] {
    assert_eq(check([0x61, 0x62, lead]), invalid(2, Some(1)))
    assert_eq(check([0x61, 0x62, lead, 0x80, 0x80]), invalid(2, Some(1)))
  }
}

///|
test "overlong forms, surrogates and values above U+10FFFF" {
  // Overlong forms of U+0000, U+07FF and U+FFFF.
  assert_eq(check([0xC0, 0x80]), invalid(0, Some(1)))
  assert_eq(check([0xE0, 0x9F, 0xBF]), invalid(0, Some(1)))
  assert_eq(check([0xF0, 0x8F, 0xBF, 0xBF]), invalid(0, Some(1)))
  // U+D800 and U+DFFF.
  assert_eq(check([0xED, 0xA0, 0x80]), invalid(0, Some(1)))
  assert_eq(check([0xED, 0xBF, 0xBF]), invalid(0, Some(1)))
  // U+110000.
  assert_eq(check([0xF4, 0x90, 0x80, 0x80]), invalid(0, Some(1)))
}

///|
test "characters interrupted by a later byte" {
  assert_eq(check([0xC3, 0x41]), invalid(0, Some(1)))
  assert_eq(check([0xE4, 0xB8, 0x41]), invalid(0, Some(2)))
  assert_eq(check([0xF0, 0x9F, 0x98, 0x41]), invalid(0, Some(3)))
  // A new lead byte interrupts too.
  assert_eq(check([0xC3, 0xC3, 0xA9]), invalid(0, Some(1)))
  assert_eq(check([0x78, 0xE4, 0x79]), invalid(1, Some(1)))
}

///|
test "input that ends inside a character" {
  assert_eq(check([0xC3]), invalid(0, None))
  assert_eq(check([0x61, 0x62, 0xE4, 0xB8]), invalid(2, None))
  assert_eq(check([0xF0, 0x9F, 0x98]), invalid(0, None))
}

///|
test "the first error is reported" {
  assert_eq(check([0x61, 0xFF, 0x62, 0xFE]), invalid(1, Some(1)))
  // After a valid three-byte character.
  assert_eq(check([0xE4, 0xB8, 0xAD, 0xFF, 0xC3]), invalid(3, Some(1)))
  // A malformed sequence comes before a truncated one.
  assert_eq(check([0xC3, 0x41, 0xE4]), invalid(0, Some(1)))
}

///|
test "chunk boundaries do not change the result" {
  let inputs = [
    b"",
    b"ascii",
    @utf8.encode("naïve 中文 😀"),
    bytes_of([0xEF, 0xBB, 0xBF, 0x61]),
    bytes_of([0x61, 0x62, 0xE4, 0xB8]),
    bytes_of([0xE4, 0xB8, 0x41]),
    bytes_of([0xF0, 0x9F, 0x98, 0x41, 0xFF]),
    bytes_of([0xE0, 0x9F, 0xBF]),
    bytes_of([0xED, 0xA0, 0x80]),
    bytes_of([0xF4, 0x90, 0x80, 0x80]),
    bytes_of([0xC3, 0xA9, 0xC3]),
  ]
  for input in inputs {
    let whole = @mbchardet.check_utf8(input[:])
    // Every split into two chunks, including empty ones.
    for cut in 0..<=input.length() {
      assert_eq(feed_in_chunks(input, [cut]), whole)
    }
    // One byte per chunk.
    let cuts = []
    for i in 1..<input.length() {
      cuts.push(i)
    }
    assert_eq(feed_in_chunks(input, cuts), whole)
  }
}

///|
test "offsets count from the start of the first chunk" {
  let validator = @mbchardet.Utf8Validator::new()
  assert_true(validator.feed(b"abc"[:]))
  assert_true(validator.feed(@utf8.encode("中")[:]))
  assert_false(validator.feed(bytes_of([0x64, 0xFF])[:]))
  assert_eq(validator.finish(), invalid(7, Some(1)))
  // A character split across chunks starts in the chunk of its lead byte.
  let split = @mbchardet.Utf8Validator::new()
  assert_true(split.feed(bytes_of([0x61, 0xF0, 0x9F])[:]))
  assert_false(split.feed(bytes_of([0x98, 0x41])[:]))
  assert_eq(split.finish(), invalid(1, Some(3)))
}

///|
test "after an error, later chunks are ignored" {
  let validator = @mbchardet.Utf8Validator::new()
  assert_false(validator.feed(bytes_of([0xFF])[:]))
  assert_false(validator.feed(b"valid"[:]))
  assert_false(validator.feed(b""[:]))
  assert_eq(validator.finish(), invalid(0, Some(1)))
}

///|
test "finish does not change the validator" {
  let validator = @mbchardet.Utf8Validator::new()
  assert_eq(validator.finish(), @mbchardet.AsciiOnly)
  assert_true(validator.feed(bytes_of([0x61, 0xE4])[:]))
  assert_eq(validator.finish(), invalid(1, None))
  assert_eq(validator.finish(), invalid(1, None))
  assert_true(validator.feed(bytes_of([0xB8, 0xAD])[:]))
  assert_eq(validator.finish(), @mbchardet.Valid)
}

///|
test "error messages" {
  assert_eq(
    @mbchardet.Utf8Error::{ valid_up_to: 4, error_len: Some(1), }.to_string(),
    "invalid UTF-8: malformed sequence of 1 byte at offset 4",
  )
  assert_eq(
    @mbchardet.Utf8Error::{ valid_up_to: 0, error_len: Some(3), }.to_string(),
    "invalid UTF-8: malformed sequence of 3 bytes at offset 0",
  )
  assert_eq(
    @mbchardet.Utf8Error::{ valid_up_to: 2, error_len: None, }.to_string(),
    "invalid UTF-8: input ends inside a character that starts at offset 2",
  )
}

///|
/// Whether core's strict decoder accepts the bytes.
fn core_accepts(bytes : Bytes) -> Bool {
  try {
    @utf8.decode(bytes[:]) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
fn assert_agrees_with_core(values : Array[Int32]) -> Unit raise {
  let bytes = bytes_of(values)
  let ours = @mbchardet.check_utf8(bytes[:]) is (AsciiOnly | Valid)
  if ours != core_accepts(bytes) {
    let hex = values.map(v => v.to_string(radix=16)).join(" ")
    fail("validity differs from @utf8.decode for bytes \{hex}")
  }
}

///|
test "validity agrees with core's UTF-8 decoder" {
  // Every input of one and two bytes.
  for a in 0..<256 {
    assert_agrees_with_core([a])
    for b in 0..<256 {
      assert_agrees_with_core([a, b])
    }
  }
  // Three and four bytes: every lead byte from C0 and every second byte,
  // followed by bytes from each range that matters.
  let tails = [0x00, 0x41, 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xFF]
  for a in 0xC0..<256 {
    for b in 0..<256 {
      for c in tails {
        assert_agrees_with_core([a, b, c])
        if a >= 0xF0 && a <= 0xF7 {
          for d in tails {
            assert_agrees_with_core([a, b, c, d])
          }
        }
      }
    }
  }
}
