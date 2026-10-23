// Helpers for the golden tests that compare with another implementation on
// mutations of short documents, whose answers tools/sniffer and
// tools/gen_xml_data.py write.

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
fn concat(parts : Array[BytesView]) -> Bytes {
  let buffer = @buffer.Buffer()
  for part in parts {
    buffer.write_bytes(part)
  }
  buffer.to_bytes()
}

///|
/// Every prefix of `seed`, from the empty one; `seed` without each byte;
/// with each byte replaced by each byte of `alphabet`; and with each byte
/// of `alphabet` inserted before each byte and at the end. The same order
/// as `mutations` in tools/sniffer/main.mjs and tools/gen_xml_data.py.
fn mutations(seed : Bytes, alphabet : Bytes) -> Array[Bytes] {
  let n = seed.length()
  let out = []
  for length in 0..<=n {
    out.push(seed[:length].to_owned())
  }
  for i in 0..<n {
    out.push(concat([seed[:i], seed[i + 1:]]))
  }
  for i in 0..<n {
    for b in alphabet {
      let copy = seed.to_array()
      copy[i] = b
      out.push(Bytes::from_array(copy))
    }
  }
  for i in 0..<=n {
    for b in alphabet {
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
/// The position in a list of names that an answer letter stands for: "a"
/// for the first, "A" for the 27th.
fn name_index(letter : Char) -> Int32 {
  if letter is ('a'..<='z') {
    letter.to_int() - 'a'.to_int()
  } else {
    letter.to_int() - 'A'.to_int() + 26
  }
}
