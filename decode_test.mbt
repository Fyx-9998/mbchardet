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

///|
/// What a new Decoder returns for each of `chunks` in turn, then `finish`.
fn streamed(
  encoding : @mbchardet.Encoding,
  chunks : Array[Bytes],
) -> Array[Result[String, @mbchardet.DecodeError]] {
  let decoder = @mbchardet.Decoder::new(encoding)
  let results = chunks.map(chunk => decoder.decode(chunk))
  results.push(decoder.finish().map(_ => ""))
  results
}

///|
test "Decoder: a character split across chunks comes with its last byte" {
  assert_eq(streamed(Gbk, [b"\xC4", b"\xE3\xBA", b"\xC3"]), [
    Ok(""),
    Ok("你"),
    Ok("好"),
    Ok(""),
  ])
  assert_eq(streamed(Utf8, [b"a\xF0", b"\x9F", b"\x98", b"\x80b"]), [
    Ok("a"),
    Ok(""),
    Ok(""),
    Ok("😀b"),
    Ok(""),
  ])
  // A surrogate pair, and a Big5 pair that gives a letter and a mark.
  assert_eq(streamed(Utf16Le, [b"=", b"\xD8\x00", b"\xDE"]), [
    Ok(""),
    Ok(""),
    Ok("😀"),
    Ok(""),
  ])
  assert_eq(streamed(Big5, [b"\x88", b"\x62"]), [
    Ok(""),
    Ok("Ê\u{304}"),
    Ok(""),
  ])
  // Escape sequences split anywhere.
  assert_eq(streamed(Iso2022Jp, [b"\x1B$", b"B$3$", b"s\x1B(", b"B!"]), [
    Ok(""),
    Ok("こ"),
    Ok("ん"),
    Ok("!"),
    Ok(""),
  ])
  // Empty chunks change nothing.
  assert_eq(streamed(Utf8, [b"", b"\xC3", b"", b"\xA9", b""]), [
    Ok(""),
    Ok(""),
    Ok(""),
    Ok("é"),
    Ok(""),
    Ok(""),
  ])
}

///|
test "Decoder: a byte order mark is removed even when split" {
  assert_eq(streamed(Utf8, [b"\xEF", b"\xBB", b"\xBFa"]), [
    Ok(""),
    Ok(""),
    Ok("a"),
    Ok(""),
  ])
  assert_eq(streamed(Utf16Be, [b"\xFE", b"\xFF\x00a"]), [
    Ok(""),
    Ok("a"),
    Ok(""),
  ])
  // Only the first mark, only of this encoding, and only in UTF-8 and
  // UTF-16: U+FEFF in GB18030 is text.
  assert_eq(streamed(Utf8, [b"\xEF\xBB\xBF", b"\xEF\xBB\xBF"]), [
    Ok(""),
    Ok("\u{FEFF}"),
    Ok(""),
  ])
  assert_eq(streamed(Utf16Be, [b"\xFF\xFE"]), [Ok("\u{FFFE}"), Ok("")])
  assert_eq(streamed(Gb18030, [b"\x84\x31", b"\x95\x33"]), [
    Ok(""),
    Ok("\u{FEFF}"),
    Ok(""),
  ])
}

///|
test "Decoder: errors count offsets from the start of the input" {
  assert_eq(streamed(Gbk, [b"ab", b"c\xFF", b"d"]), [
    Ok("ab"),
    refused(Gbk, 3, Some(1)),
    // Once refused, the decoder keeps the error.
    refused(Gbk, 3, Some(1)),
    refused(Gbk, 3, Some(1)),
  ])
  // The malformed sequence starts in an earlier chunk; the byte that
  // interrupts it is not part of it.
  assert_eq(streamed(Utf8, [b"x\xE4", b"\xB8", b"A"]), [
    Ok("x"),
    Ok(""),
    refused(Utf8, 1, Some(2)),
    refused(Utf8, 1, Some(2)),
  ])
  // Offsets count the byte order mark.
  assert_eq(streamed(Utf8, [b"\xEF\xBB\xBF", b"a\xFF"]), [
    Ok(""),
    refused(Utf8, 4, Some(1)),
    refused(Utf8, 4, Some(1)),
  ])
  // A useless ISO-2022-JP escape sequence in the chunk before.
  assert_eq(streamed(Iso2022Jp, [b"a\x1B$B", b"\x1B(B"]), [
    Ok("a"),
    refused(Iso2022Jp, 1, Some(3)),
    refused(Iso2022Jp, 1, Some(3)),
  ])
}

///|
test "Decoder: only finish refuses input that ends inside a character" {
  assert_eq(streamed(Utf8, [b"a", b"\xF0\x9F\x98"]), [
    Ok("a"),
    Ok(""),
    refused(Utf8, 1, None),
  ])
  let decoder = @mbchardet.Decoder::new(Utf16Le)
  assert_eq(decoder.decode(b"a\x00b"), Ok("a"))
  assert_eq(
    decoder.finish(),
    Err({ encoding: Utf16Le, valid_up_to: 2, error_len: None, }),
  )
  assert_eq(
    decoder.finish(),
    Err({ encoding: Utf16Le, valid_up_to: 2, error_len: None, }),
  )
  assert_eq(decoder.decode(b"\x00"), refused(Utf16Le, 2, None))
  // Finishing a complete input can be repeated.
  let complete = @mbchardet.Decoder::new(Utf8)
  assert_eq(complete.decode(b"ok"), Ok("ok"))
  assert_eq(complete.finish(), Ok(()))
  assert_eq(complete.finish(), Ok(()))
}

///|
test "Decoder: the replacement encoding refuses its first byte" {
  assert_eq(streamed(Replacement, [b"", b""]), [Ok(""), Ok(""), Ok("")])
  assert_eq(streamed(Replacement, [b"", b"abc"]), [
    Ok(""),
    refused(Replacement, 0, Some(1)),
    refused(Replacement, 0, Some(1)),
  ])
}

///|
test "Decoder: every split of an input gives what decode gives" {
  let inputs : Array[(@mbchardet.Encoding, Bytes)] = [
    (Utf8, b"\xEF\xBB\xBFGr\xC3\xBC\xC3\x9Fe \xF0\x9F\x98\x80!"),
    (Utf8, b"ok \xE4\xB8 no"),
    (Utf16Le, b"\xFF\xFE=\xD8\x00\xDEa\x00"),
    (Utf16Be, b"\xD8=\x00a"),
    (Gb18030, b"\xC4\xE3\x81\x30\x81\x30\x84\x31\x95\x33"),
    (Big5, b"\xA4\x40\x88\x62\x88\x64 \x81"),
    (ShiftJis, b"\x82\xB1\x82\xF1\xB6\xDE"),
    (EucJp, b"\xA4\xB3\x8F\xA1\xC1\x8E\xB6"),
    (Iso2022Jp, b"a\x1B$B$3$s\x1B(B!\x1B(J\\"),
    (Iso2022Jp, b"a\x1B$B\x1B(B"),
    (EucKr, b"\xC5\xD7\xBD\xBA\xC6"),
    (Windows1253, b"\xC1\xAA\xE1"),
  ]
  for case in inputs {
    let (encoding, input) = case
    let whole = encoding.decode(input)
    for i in 0..<=input.length() {
      for j in i..<=input.length() {
        let decoder = @mbchardet.Decoder::new(encoding)
        let text = StringBuilder()
        let mut result = Ok("")
        for chunk in [input[:i], input[i:j], input[j:]] {
          match decoder.decode(chunk) {
            Ok(part) => text.write_string(part)
            Err(error) => {
              result = Err(error)
              break
            }
          }
        }
        if result is Ok(_) {
          result = decoder.finish().map(_ => text.to_string())
        }
        assert_eq(result, whole, msg="\{encoding} split at \{i} and \{j}")
      }
    }
  }
}

///|
test "Decoder: every character of UTF-8 and UTF-16, split anywhere" {
  let all = StringBuilder()
  for code_point in 0..<=0x10FFFF {
    if code_point < 0xD800 || code_point > 0xDFFF {
      all.write_char(code_point.unsafe_to_char())
    }
  }
  let text = all.to_string()
  let little = Buffer()
  let big = Buffer()
  for i in 0..<text.length() {
    let unit = text.code_unit_at(i).to_int()
    little.write_byte((unit & 0xFF).to_byte())
    little.write_byte((unit >> 8).to_byte())
    big.write_byte((unit >> 8).to_byte())
    big.write_byte((unit & 0xFF).to_byte())
  }
  let inputs : Array[(@mbchardet.Encoding, Bytes)] = [
    (Utf8, @utf8.encode(text)),
    (Utf16Le, little.to_bytes()),
    (Utf16Be, big.to_bytes()),
  ]
  for case in inputs {
    let (encoding, input) = case
    // Chunks of 7 bytes end at every position inside a character of 2, 3
    // or 4 bytes somewhere in the input.
    let decoder = @mbchardet.Decoder::new(encoding)
    let decoded = StringBuilder()
    let mut start = 0
    while start < input.length() {
      let end = if input.length() - start > 7 {
        start + 7
      } else {
        input.length()
      }
      match decoder.decode(input[start:end]) {
        Ok(part) => decoded.write_string(part)
        Err(error) => fail("\{encoding}: \{error}")
      }
      start = end
    }
    assert_eq(decoder.finish(), Ok(()))
    // Compared without printing a few megabytes on failure.
    assert_true(decoded.to_string() == text, msg="\{encoding}")
  }
}

///|
test "panic Decoder::decode after finish" {
  let decoder = @mbchardet.Decoder::new(Utf8)
  decoder.finish() |> ignore
  decoder.decode(b"a") |> ignore
}
