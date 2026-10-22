// Checks the GBK and Big5 decoders against encoding_rs 0.8.42: the hashes in
// golden_trace_wbtest.mbt come from tools/golden, which feeds the same byte
// sequences to encoding_rs and hashes its answers the same way.

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
/// Hashes one answer like tools/golden; true if it was malformed.
fn record(step : Step, hash : Fnv) -> Bool {
  match step {
    Pending => {
      hash.word(0)
      hash.word(0)
      false
    }
    Unit(u) => {
      hash.word(0)
      hash.word(1)
      hash.word(u)
      false
    }
    Units(u, v) => {
      hash.word(0)
      hash.word(2)
      hash.word(u)
      hash.word(v)
      false
    }
    Malformed(length) => {
      hash.word(1)
      hash.word(length)
      hash.word(0)
      true
    }
  }
}

///|
/// GBK stops at the first malformed sequence, as its candidate resets the
/// decoder or gives up there.
fn trace_gbk(sequence : Array[Int32], hash : Fnv) -> Unit {
  let decoder = GbkDecoder::new()
  for b in sequence {
    if record(decoder.feed(b), hash) {
      return
    }
  }
  hash.word(2)
  hash.word(if decoder.incomplete() { 1 } else { 0 })
}

///|
fn trace_big5(sequence : Array[Int32], hash : Fnv) -> Unit {
  let decoder = Big5Decoder::new()
  for b in sequence {
    record(decoder.feed(b), hash) |> ignore
  }
  hash.word(2)
  hash.word(if decoder.incomplete() { 1 } else { 0 })
}

///|
fn hash_of(
  trace : (Array[Int32], Fnv) -> Unit,
  sequences : Array[Array[Int32]],
) -> UInt64 {
  let hash = Fnv::new()
  for sequence in sequences {
    trace(sequence, hash)
  }
  hash.value
}

///|
fn singles() -> Array[Array[Int32]] {
  Array::makei(256, b => [b])
}

///|
fn pairs(lead : Int32) -> Array[Array[Int32]] {
  Array::makei(256, b => [lead, b])
}

///|
fn inclusive(from : Int32, to : Int32) -> Array[Int32] {
  Array::makei(to - from + 1, i => from + i)
}

///|
/// Every second byte 0x30 to 0x39, then third and fourth bytes from the
/// lists below; first bytes 0x81 to 0x84 cover every BMP pointer.
fn gb18030_four_byte(first : Int32) -> Array[Array[Int32]] {
  let all = first <= 0x84
  let thirds = if all {
    inclusive(0x81, 0xFE) + [0x00, 0x30, 0x7F, 0x80, 0xFF]
  } else {
    [0x81, 0x82, 0xA0, 0xA1, 0xFD, 0xFE, 0x30, 0x80, 0xFF]
  }
  let fourths = if all {
    inclusive(0x30, 0x39) + [0x2F, 0x3A, 0x80, 0xFF]
  } else {
    [0x30, 0x35, 0x39, 0x2F, 0x3A, 0xFF]
  }
  let sequences = []
  for second in 0x30..<=0x39 {
    for third in thirds {
      if third >= 0x81 && third <= 0xFE {
        for fourth in fourths {
          sequences.push([first, second, third, fourth])
        }
      } else {
        sequences.push([first, second, third])
      }
    }
  }
  sequences
}

///|
/// Each lead, a second byte from the list, then two more bytes.
fn big5_after(lead : Int32) -> Array[Array[Int32]] {
  let sequences = []
  for second in [0x00, 0x30, 0x7F, 0x80, 0xA0, 0xFF, 0x40, 0xA1] {
    for next in [0x41, 0x81, 0xA4, 0xFF] {
      sequences.push([lead, second, next, 0x40])
    }
  }
  sequences
}

///|
fn assert_hash(
  what : String,
  lead : Int32,
  actual : UInt64,
  expected : UInt64,
) -> Unit raise {
  if actual != expected {
    fail(
      "\{what} with first byte \{lead.to_string(radix=16)} differs from encoding_rs",
    )
  }
}

///|
test "GBK decoder answers like encoding_rs" {
  assert_eq(hash_of(trace_gbk, singles()), golden_gbk_single)
  for i, expected in golden_gbk_pairs {
    let lead = 0x81 + i
    assert_hash("two bytes", lead, hash_of(trace_gbk, pairs(lead)), expected)
  }
  for i, expected in golden_gbk_four_byte {
    let first = 0x81 + i
    assert_hash(
      "four bytes",
      first,
      hash_of(trace_gbk, gb18030_four_byte(first)),
      expected,
    )
  }
}

///|
test "Big5 decoder answers like encoding_rs" {
  assert_eq(hash_of(trace_big5, singles()), golden_big5_single)
  for i, expected in golden_big5_pairs {
    let lead = 0x81 + i
    assert_hash("two bytes", lead, hash_of(trace_big5, pairs(lead)), expected)
  }
  for i, expected in golden_big5_after {
    let lead = 0x81 + i
    assert_hash(
      "two bytes and more",
      lead,
      hash_of(trace_big5, big5_after(lead)),
      expected,
    )
  }
}

///|
fn decode_steps(decoder : GbkDecoder, bytes : Array[Int32]) -> Array[Step] {
  bytes.map(b => decoder.feed(b))
}

///|
test "GBK examples" {
  // 你 (U+4F60) and the euro sign
  assert_true(
    decode_steps(GbkDecoder::new(), [0xC4, 0xE3, 0x80])
    is [Pending, Unit(0x4F60), Unit(0x20AC)],
  )
  // Four bytes: U+0080, and U+10000 as a surrogate pair
  assert_true(
    decode_steps(GbkDecoder::new(), [0x81, 0x30, 0x81, 0x30])
    is [Pending, Pending, Pending, Unit(0x80)],
  )
  assert_true(
    decode_steps(GbkDecoder::new(), [0x90, 0x30, 0x81, 0x30])
    is [Pending, Pending, Pending, Units(0xD800, 0xDC00)],
  )
  // GB18030-2022 maps A6 D9 to U+FE10 instead of a private use code point.
  assert_true(
    decode_steps(GbkDecoder::new(), [0xA6, 0xD9]) is [Pending, Unit(0xFE10)],
  )
  // An ASCII byte after a lead is not part of the malformed sequence.
  assert_true(
    decode_steps(GbkDecoder::new(), [0x81, 0x20]) is [_, Malformed(1)],
  )
  assert_true(
    decode_steps(GbkDecoder::new(), [0x81, 0xFF]) is [_, Malformed(2)],
  )
  assert_true(decode_steps(GbkDecoder::new(), [0xFF]) is [Malformed(1)])
  let open = GbkDecoder::new()
  open.feed(0xC4) |> ignore
  assert_true(open.incomplete())
}

///|
test "Big5 examples" {
  // 你 (U+4F60)
  assert_true(
    decode_steps_big5(Big5Decoder::new(), [0xA7, 0x41])
    is [Pending, Unit(0x4F60)],
  )
  // Pointer 1133 decodes to two code points.
  assert_true(
    decode_steps_big5(Big5Decoder::new(), [0x88, 0x62])
    is [Pending, Units(0xCA, 0x304)],
  )
  // 0x87 0x45, pointer 947, is U+27267, outside the BMP.
  assert_true(
    decode_steps_big5(Big5Decoder::new(), [0x87, 0x45])
    is [Pending, Units(0xD85C, 0xDE67)],
  )
  // Pointer 0 has no mapping; 0x40 is ASCII, so the sequence is one byte.
  assert_true(
    decode_steps_big5(Big5Decoder::new(), [0x81, 0x40]) is [_, Malformed(1)],
  )
  assert_true(
    decode_steps_big5(Big5Decoder::new(), [0x81, 0xA1]) is [_, Malformed(2)],
  )
  assert_true(decode_steps_big5(Big5Decoder::new(), [0x80]) is [Malformed(1)])
}

///|
fn decode_steps_big5(
  decoder : Big5Decoder,
  bytes : Array[Int32],
) -> Array[Step] {
  bytes.map(b => decoder.feed(b))
}
