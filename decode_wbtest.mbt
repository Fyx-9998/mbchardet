///|
/// A decoder from `encoding` as if `before` bytes had already been decoded,
/// without decoding that many.
fn decoder_after(encoding : Encoding, before : Int64) -> Decoder {
  let decoder = Decoder::new(encoding)
  decoder.consumed = before
  decoder.before_bom = false
  decoder
}

///|
test "Decoder: offsets past 2 GiB" {
  let before = 0x7FFFFFF0L
  // A chunk that takes the input past 2147483647 bytes is decoded.
  let ascii = decoder_after(Gbk, before)
  assert_eq(
    ascii.decode(b"0123456789abcdef0123456789abcdef"),
    Ok("0123456789abcdef0123456789abcdef"),
  )
  assert_eq(ascii.consumed, before + 32)
  // Malformed sequences past it, in the table of a single-byte encoding and
  // with a byte decoder.
  for case in [(Windows1253, b"\xAA"), (Gbk, b"\xFF"), (Utf8, b"\xFF")] {
    let (encoding, bad) = case
    let decoder = decoder_after(encoding, before)
    assert_eq(
      decoder.decode(b"0123456789abcdef" + bad),
      Err({ encoding, valid_up_to: 0x80000000L, error_len: Some(1), }),
    )
  }
  // A sequence that starts in one chunk and is cut at the end of the input,
  // and one that a byte in the next chunk interrupts.
  let cut = decoder_after(Gbk, 0x7FFFFFFFL)
  assert_eq(cut.decode(b"a\xC4"), Ok("a"))
  assert_eq(
    cut.finish(),
    Err({ encoding: Gbk, valid_up_to: 0x80000000L, error_len: None, }),
  )
  let interrupted = decoder_after(Utf8, 0x7FFFFFFFL)
  assert_eq(interrupted.decode(b"a\xE4\xB8"), Ok("a"))
  assert_eq(
    interrupted.decode(b"A"),
    Err({ encoding: Utf8, valid_up_to: 0x80000000L, error_len: Some(2), }),
  )
  // The escape sequence ISO-2022-JP blames, three bytes back.
  let escapes = decoder_after(Iso2022Jp, 0xFFFFFFFFL)
  assert_eq(escapes.decode(b"a\x1B$B"), Ok("a"))
  assert_eq(
    escapes.decode(b"\x1B(B"),
    Err({ encoding: Iso2022Jp, valid_up_to: 0x100000000L, error_len: Some(3), }),
  )
}
