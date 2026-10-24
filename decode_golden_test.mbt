// Compares Encoding::decode with the decoders of encoding_rs 0.8.42 on the
// inputs of decode_data_test.mbt, which tools/golden writes: a few prefixes
// followed by every sequence of one or two bytes, and mutations of seeds as
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
/// Hashes what decoding `input` gives like tools/golden: [0, length, UTF-16
/// code units...] for text, [1, offset, length or -1] for an error.
fn hash_decode(
  hash : Fnv,
  encoding : @mbchardet.Encoding,
  input : BytesView,
) -> Unit {
  match encoding.decode(input) {
    Ok(text) => {
      hash.word(0)
      hash.word(text.length())
      for i in 0..<text.length() {
        hash.word(text.code_unit_at(i).to_int())
      }
    }
    Err(error) => {
      hash.word(1)
      hash.word(error.valid_up_to)
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
    for suffix in 0..<(1 << (8 * n)) {
      for i in 0..<n {
        input[prefix.length() + i] = (suffix >> (8 * (n - 1 - i))).to_byte()
      }
      hash_decode(hash, encoding, Bytes::from_array(input))
    }
    if hash.value != expected {
      fail(
        "\{name}: \{bytes_literal(prefix)} followed by each sequence of \{n} bytes does not decode as in encoding_rs",
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
    for mutation in mutations {
      hash_decode(hash, encoding, mutation)
    }
    if hash.value != expected {
      fail(
        "\{name}: the mutations of \{bytes_literal(seed)} do not decode as in encoding_rs",
      )
    }
    total += mutations.length()
  }
  assert_eq(decode_seeds.length(), 88)
  assert_eq(total, 96850)
}
