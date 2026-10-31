// Compares Encoding::decode, and a Decoder fed the same input in chunks,
// with the decoders of encoding_rs 0.8.42 on the inputs of
// decode_data_test.mbt, which tools/golden writes: a few prefixes followed
// by every sequence of one or two bytes, and mutations of seeds as
// mutation_test.mbt describes them. Both sides hash what they give the same
// way, so a failure names a group or a seed but not the input in it.

///|
/// FNV-1a over 32-bit words, each as four little-endian bytes.
priv struct Fnv {
  mut value : UInt64
}

///|
fn Fnv::new() -> Fnv {
  { value: 0xCBF29CE484222325UL, }
}

///|
fn Fnv::word(self : Fnv, word : Int32) -> Unit {
  let mut w = word
  for _ in 0..<4 {
    self.value = (self.value ^ (w & 0xFF).to_uint64()) * 0x100000001B3UL
    w = w >> 8
  }
}

///|
/// What a `Decoder` gives for `input` fed in chunks of `size` bytes: the
/// text of all the chunks, or the first error.
fn decode_in_chunks(
  encoding : @mbchardet.Encoding,
  input : BytesView,
  size : Int32,
) -> Result[String, @mbchardet.DecodeError] {
  let decoder = @mbchardet.Decoder::new(encoding)
  let text = StringBuilder()
  let mut start = 0
  while start < input.length() {
    let end = if input.length() - start > size {
      start + size
    } else {
      input.length()
    }
    match decoder.decode(input[start:end]) {
      Ok(chunk) => text.write_string(chunk)
      Err(error) => return Err(error)
    }
    start = end
  }
  match decoder.finish() {
    Ok(_) => Ok(text.to_string())
    Err(error) => Err(error)
  }
}

///|
/// Hashes what decoding gives like tools/golden: [0, length, UTF-16 code
/// units...] for text, [1, offset, length or -1] for an error.
fn hash_decode(
  hash : Fnv,
  decoded : Result[String, @mbchardet.DecodeError],
) -> Unit {
  match decoded {
    Ok(text) => {
      hash.word(0)
      hash.word(text.length())
      for i in 0..<text.length() {
        hash.word(text.code_unit_at(i).to_int())
      }
    }
    Err(error) => {
      hash.word(1)
      hash.word(error.valid_up_to.to_int())
      hash.word(error.error_len.unwrap_or(-1))
    }
  }
}

///|
fn encoding_named(name : String) -> @mbchardet.Encoding {
  guard @mbchardet.Encoding::from_label(name) is Some(encoding) &&
    encoding.name() == name else {
    abort("\{name} is not the name of an encoding")
  }
  encoding
}

///|
test "every input of one or two bytes after a prefix decodes as in encoding_rs" {
  for entry in decode_groups {
    let (name, prefix, n, expected) = entry
    let encoding = encoding_named(name)
    let input = FixedArray::make(prefix.length() + n, b'\x00')
    for i, b in prefix {
      input[i] = b
    }
    let hash = Fnv::new()
    // A Decoder fed one byte at a time.
    let streamed = Fnv::new()
    for suffix in 0..<(1 << (8 * n)) {
      for i in 0..<n {
        input[prefix.length() + i] = (suffix >> (8 * (n - 1 - i))).to_byte()
      }
      let bytes = Bytes::from_array(input)
      hash_decode(hash, encoding.decode(bytes))
      hash_decode(streamed, decode_in_chunks(encoding, bytes, 1))
    }
    if hash.value != expected {
      fail(
        "\{name}: \{bytes_literal(prefix)} followed by each sequence of \{n} bytes does not decode as in encoding_rs",
      )
    }
    if streamed.value != expected {
      fail(
        "\{name}: \{bytes_literal(prefix)} followed by each sequence of \{n} bytes does not decode as in encoding_rs when fed one byte at a time",
      )
    }
  }
  assert_eq(decode_groups.length(), 58)
}

///|
test "seeds and their mutations decode as in encoding_rs" {
  let mut total = 0
  for entry in decode_seeds {
    let (name, seed, text, expected) = entry
    let encoding = encoding_named(name)
    assert_eq(encoding.decode(seed), Ok(text))
    let mutations = mutations(seed, decode_alphabet)
    let hash = Fnv::new()
    // A Decoder fed each mutation in chunks of 1, 2, 3 or 7 bytes, or whole,
    // in turn.
    let streamed = Fnv::new()
    for i, mutation in mutations {
      hash_decode(hash, encoding.decode(mutation))
      let size = [1, 2, 3, 7, mutation.length() + 1][i % 5]
      hash_decode(streamed, decode_in_chunks(encoding, mutation, size))
    }
    if hash.value != expected {
      fail(
        "\{name}: the mutations of \{bytes_literal(seed)} do not decode as in encoding_rs",
      )
    }
    if streamed.value != expected {
      fail(
        "\{name}: the mutations of \{bytes_literal(seed)} do not decode as in encoding_rs when fed in chunks",
      )
    }
    total += mutations.length()
  }
  assert_eq(decode_seeds.length(), 88)
  assert_eq(total, 96850)
}
