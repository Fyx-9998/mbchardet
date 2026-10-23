// Compares prescan_html with the cases of html5lib-tests and
// web-platform-tests, and with what html-encoding-sniffer 7.0.0 finds for
// mutations of short documents: the inputs in prescan_data_test.mbt,
// written by tools/sniffer.

///|
/// The encoding of `bytes` when the transport layer gives none: a byte
/// order mark, then the prescan.
fn sniffed(bytes : BytesView) -> @mbchardet.Encoding? {
  match @mbchardet.sniff_bom(bytes) {
    Some((encoding, _)) => Some(encoding)
    None => @mbchardet.prescan_html(bytes)
  }
}

///|
/// `bytes` as a MoonBit literal.
fn bytes_literal(bytes : BytesView) -> String {
  let s = StringBuilder()
  s.write_string("b\"")
  for b in bytes {
    if b >= 0x20 && b < 0x7F && b != b'"' && b != b'\\' {
      s.write_char(b.to_int().unsafe_to_char())
    } else {
      s.write_string("\\x")
      s.write_string(
        b.to_int().to_string(radix=16).to_upper().pad_start(2, '0'),
      )
    }
  }
  s.write_string("\"")
  s.to_string()
}

///|
fn show_encoding(encoding : @mbchardet.Encoding?) -> String {
  match encoding {
    Some(e) => e.name()
    None => "no encoding"
  }
}

///|
test "the prescan passes the cases of html5lib-tests and web-platform-tests" {
  assert_eq(prescan_conformance.length(), 115)
  for case in prescan_conformance {
    let (id, input, expected) = case
    // Both suites expect windows-1252 when nothing is declared:
    // html5lib-tests as the default encoding, web-platform-tests as the
    // encoding of the document around the frame.
    let found = sniffed(input).unwrap_or(@mbchardet.Windows1252).name()
    if found != expected {
      fail("\{id}: \{found}, the suite expects \{expected}")
    }
  }
}

///|
fn concat(parts : Array[BytesView]) -> Bytes {
  let buffer = @buffer.Buffer()
  for part in parts {
    buffer.write_bytes(part)
  }
  buffer.to_bytes()
}

///|
/// Every prefix of `seed`, from the empty one; `seed` without each byte;
/// with each byte replaced by each byte of prescan_alphabet; and with each
/// byte of prescan_alphabet inserted before each byte and at the end. The
/// same order as `mutations` in tools/sniffer/main.mjs.
fn prescan_mutations(seed : Bytes) -> Array[Bytes] {
  let n = seed.length()
  let out = []
  for length in 0..<=n {
    out.push(seed[:length].to_owned())
  }
  for i in 0..<n {
    out.push(concat([seed[:i], seed[i + 1:]]))
  }
  for i in 0..<n {
    for b in prescan_alphabet {
      let copy = seed.to_array()
      copy[i] = b
      out.push(Bytes::from_array(copy))
    }
  }
  for i in 0..<=n {
    for b in prescan_alphabet {
      out.push(concat([seed[:i], [b], seed[i:]]))
    }
  }
  out
}

///|
/// The answers of a seed, one letter for each mutation.
fn decode_runs(runs : String) -> Array[Char] {
  let answers = []
  let mut letter = ' '
  let mut count = 0
  for c in runs {
    if c is ('0'..<='9') {
      count = count * 10 + (c.to_int() - '0'.to_int())
    } else {
      for _ in 0..<count {
        answers.push(letter)
      }
      letter = c
      count = 0
    }
  }
  for _ in 0..<count {
    answers.push(letter)
  }
  answers
}

///|
test "the prescan matches html-encoding-sniffer 7.0.0" {
  let names = prescan_names.map(name => @mbchardet.Encoding::from_label(name))
  let mut total = 0
  for entry in prescan_seeds {
    let (seed, runs) = entry
    let answers = decode_runs(runs)
    let mutations = prescan_mutations(seed)
    assert_eq(mutations.length(), answers.length())
    for i, mutation in mutations {
      let expected = match answers[i] {
        '-' => None
        c if c is ('a'..<='z') => names[c.to_int() - 'a'.to_int()]
        c => names[c.to_int() - 'A'.to_int() + 26]
      }
      let found = sniffed(mutation)
      if found != expected {
        fail(
          "\{bytes_literal(mutation)} (mutation \{i} of \{bytes_literal(seed)}): \{show_encoding(found)}, html-encoding-sniffer \{show_encoding(expected)}",
        )
      }
    }
    total += mutations.length()
  }
  assert_eq(prescan_seeds.length(), 131)
  assert_eq(total, 471093)
}
