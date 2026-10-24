///|
fn decoded(
  encoding : @mbchardet.Encoding,
  bytes : Bytes,
) -> Result[String, @mbchardet.DecodeError] {
  encoding.decode(bytes)
}

///|
fn refused(
  encoding : @mbchardet.Encoding,
  valid_up_to : Int32,
  error_len : Int32?,
) -> Result[String, @mbchardet.DecodeError] {
  Err({ encoding, valid_up_to, error_len, })
}

///|
test "decode: valid input gives its text" {
  assert_eq(decoded(Gbk, b"\xC4\xE3\xBA\xC3"), Ok("你好"))
  assert_eq(
    decoded(ShiftJis, b"\x82\xB1\x82\xF1\x82\xC9\x82\xBF\x82\xCD"),
    Ok("こんにちは"),
  )
  assert_eq(decoded(Windows1252, b"caf\xE9 \x80"), Ok("café €"))
  assert_eq(decoded(Utf8, b"na\xC3\xAFve"), Ok("naïve"))
  // Four Big5 pairs give a letter and a combining mark.
  assert_eq(decoded(Big5, b"\x88\x62"), Ok("Ê\u{304}"))
  // x-user-defined keeps every byte, those above 0x7F in the Private Use
  // Area.
  assert_eq(decoded(XUserDefined, b"a\x80\xFF"), Ok("a\u{F780}\u{F7FF}"))
}

///|
test "decode: every encoding but UTF-16 and replacement reads ASCII text unchanged" {
  for encoding in @mbchardet.Encoding::all() {
    match encoding {
      Utf16Be | Utf16Le | Replacement => ()
      _ =>
        assert_eq(
          encoding.decode(b"Plain text, 123.\r\n"),
          Ok("Plain text, 123.\r\n"),
        )
    }
  }
}

///|
test "decode: the first malformed sequence is refused" {
  // A byte that cannot start a character.
  assert_eq(decoded(Gbk, b"ab\xFFcd"), refused(Gbk, 2, Some(1)))
  // A byte with no code point in a single-byte encoding.
  assert_eq(decoded(Windows1253, b"a\xAA"), refused(Windows1253, 1, Some(1)))
  // A four-byte GB18030 sequence beyond the last code point.
  assert_eq(decoded(Gb18030, b"\x84\x31\xA5\x30"), refused(Gb18030, 0, Some(4)))
  // A lead byte that an ASCII byte interrupts: the ASCII byte is not part
  // of the malformed sequence.
  assert_eq(decoded(Gbk, b"\xC4\xE3\xC4 "), refused(Gbk, 2, Some(1)))
  assert_eq(decoded(Utf8, b"\xE1\x80A"), refused(Utf8, 0, Some(2)))
  assert_eq(decoded(EucJp, b"\x8F\xA1 "), refused(EucJp, 0, Some(2)))
}

///|
test "decode: input that ends inside a sequence is refused" {
  assert_eq(decoded(Gbk, b"\xC4\xE3\xC4"), refused(Gbk, 2, None))
  assert_eq(decoded(Utf8, b"a\xF0\x9F\x98"), refused(Utf8, 1, None))
  assert_eq(decoded(Utf16Le, b"a\x00b"), refused(Utf16Le, 2, None))
  // An escape sequence cut short.
  assert_eq(decoded(Iso2022Jp, b"ab\x1B("), refused(Iso2022Jp, 2, None))
}

///|
test "decode: a byte order mark of the encoding is removed" {
  assert_eq(decoded(Utf8, b"\xEF\xBB\xBFa"), Ok("a"))
  assert_eq(decoded(Utf16Le, b"\xFF\xFEa\x00"), Ok("a"))
  assert_eq(decoded(Utf16Be, b"\xFE\xFF\x00a"), Ok("a"))
  // Only at the start, and only the mark of this encoding.
  assert_eq(decoded(Utf8, b"a\xEF\xBB\xBF"), Ok("a\u{FEFF}"))
  assert_eq(decoded(Utf16Be, b"\xFF\xFE\x00a"), Ok("\u{FFFE}a"))
  // Offsets count the mark.
  assert_eq(decoded(Utf8, b"\xEF\xBB\xBFa\xFF"), refused(Utf8, 4, Some(1)))
}

///|
test "decode: UTF-16 surrogates" {
  assert_eq(decoded(Utf16Le, b"=\xD8\x00\xDE"), Ok("😀"))
  assert_eq(decoded(Utf16Be, b"\xD8=\xDE\x00"), Ok("😀"))
  // A lead surrogate without a trail surrogate is malformed, not the code
  // unit after it; so is a trail surrogate alone.
  assert_eq(decoded(Utf16Le, b"=\xD8a\x00"), refused(Utf16Le, 0, Some(2)))
  assert_eq(decoded(Utf16Be, b"\x00a\xDE\x00"), refused(Utf16Be, 2, Some(2)))
}

///|
test "decode: ISO-2022-JP escape sequences" {
  assert_eq(decoded(Iso2022Jp, b"\x1B$B$3$s\x1B(B!"), Ok("こん!"))
  assert_eq(decoded(Iso2022Jp, b"\x1B(J\\~\x1B(B"), Ok("¥‾"))
  assert_eq(decoded(Iso2022Jp, b"\x1B(Z"), refused(Iso2022Jp, 0, Some(1)))
  // An escape sequence right after another makes the first one useless,
  // which is the malformed sequence.
  assert_eq(
    decoded(Iso2022Jp, b"a\x1B$B\x1B(B"),
    refused(Iso2022Jp, 1, Some(3)),
  )
}

///|
test "decode: the replacement encoding refuses all but empty input" {
  assert_eq(decoded(Replacement, b""), Ok(""))
  assert_eq(decoded(Replacement, b"abc"), refused(Replacement, 0, Some(1)))
}

///|
test "decode: the text of a page sniff_html finds the encoding of" {
  let page = b"<meta charset=\"shift_jis\"><p>\x82\xB1\x82\xF1</p>"
  let sniffed = @mbchardet.sniff_html(page)
  assert_eq(
    sniffed.encoding.decode(page),
    Ok("<meta charset=\"shift_jis\"><p>こん</p>"),
  )
}

///|
test "DecodeError describes the error" {
  let errors : Array[@mbchardet.DecodeError] = [
    { encoding: Gbk, valid_up_to: 2, error_len: Some(1), },
    { encoding: Iso2022Jp, valid_up_to: 0, error_len: Some(3), },
    { encoding: Utf16Le, valid_up_to: 2, error_len: None, },
    { encoding: Replacement, valid_up_to: 0, error_len: Some(1), },
  ]
  inspect(
    errors.map(error => error.to_string()).join("\n"),
    content=(
      #|invalid GBK: malformed sequence of 1 byte at offset 2
      #|invalid ISO-2022-JP: malformed sequence of 3 bytes at offset 0
      #|invalid UTF-16LE: input ends inside a sequence that starts at offset 2
      #|not decoded: the replacement encoding stands for ISO-2022-KR, ISO-2022-CN and HZ-GB-2312, whose content the Encoding Standard does not decode
    ),
  )
}
