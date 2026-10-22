// Checks the Shift_JIS, EUC-JP and ISO-2022-JP decoders against encoding_rs
// 0.8.42, with the hashes tools/golden writes to golden_trace_wbtest.mbt.
// Fnv, record, hash_of, singles, pairs, after and assert_hash are in
// cjk_decoder_wbtest.mbt.

///|
/// Shift_JIS and EUC-JP go on after a malformed sequence, as their
/// candidates do.
fn trace_shift_jis(sequence : Array[Int32], hash : Fnv) -> Unit {
  let decoder = ShiftJisDecoder::new()
  for b in sequence {
    record(decoder.feed(b), hash) |> ignore
  }
  hash.word(2)
  hash.word(if decoder.incomplete() { 1 } else { 0 })
}

///|
fn trace_euc_jp(sequence : Array[Int32], hash : Fnv) -> Unit {
  let decoder = EucJpDecoder::new()
  for b in sequence {
    record(decoder.feed(b), hash) |> ignore
  }
  hash.word(2)
  hash.word(if decoder.incomplete() { 1 } else { 0 })
}

///|
/// ISO-2022-JP stops at the first malformed sequence, where its candidate
/// gives up.
fn trace_iso_2022_jp(sequence : Array[Int32], hash : Fnv) -> Unit {
  let decoder = Iso2022JpDecoder::new()
  for b in sequence {
    if record(decoder.feed(b), hash) {
      return
    }
  }
  hash.word(2)
  hash.word(if decoder.incomplete() { 1 } else { 0 })
}

///|
/// EUC-JP JIS X 0212: 0x8F, a lead, then every byte.
fn jis0212(lead : Int32) -> Array[Array[Int32]] {
  Array::makei(256, t => [0x8F, lead, t])
}

///|
/// The ISO-2022-JP escape sequences that select ASCII, Roman, katakana and
/// JIS X 0208 (two of them).
let designations : Array[Array[Int32]] = [
  [0x1B, 0x28, 0x42],
  [0x1B, 0x28, 0x4A],
  [0x1B, 0x28, 0x49],
  [0x1B, 0x24, 0x40],
  [0x1B, 0x24, 0x42],
]

///|
/// ESC followed by every byte, and ESC ( and ESC $ followed by every byte.
fn iso_2022_jp_escapes() -> Array[Array[Int32]] {
  let sequences = []
  for x in 0..<256 {
    sequences.push([0x1B, x])
    sequences.push([0x1B, 0x28, x])
    sequences.push([0x1B, 0x24, x])
  }
  sequences
}

///|
/// A designation followed by every byte.
fn iso_2022_jp_after(designation : Array[Int32]) -> Array[Array[Int32]] {
  Array::makei(256, b => designation + [b])
}

///|
/// JIS X 0208 selected, a lead, then every byte.
fn iso_2022_jp_jis0208(lead : Int32) -> Array[Array[Int32]] {
  Array::makei(256, t => [0x1B, 0x24, 0x42, lead, t])
}

///|
/// Pairs of designations with nothing, a letter, a JIS X 0208 pair or a
/// lone lead between them, then inputs that end inside a sequence.
fn iso_2022_jp_sequences() -> Array[Array[Int32]] {
  let sequences = []
  for first in designations {
    for second in designations {
      for between in [[], [0x41], [0x21, 0x21], [0x21]] {
        sequences.push(first + between + second)
      }
    }
  }
  for
    tail in [
      [0x1B],
      [0x1B, 0x28],
      [0x1B, 0x24],
      [0x1B, 0x24, 0x42, 0x30],
      [0x41, 0x1B],
      [0x1B, 0x28, 0x42, 0x41],
    ] {
    sequences.push(tail)
  }
  sequences
}

///|
test "Shift_JIS decoder answers like encoding_rs" {
  assert_eq(hash_of(trace_shift_jis, singles()), golden_shift_jis_single)
  for i, expected in golden_shift_jis_pairs {
    let lead = 0x81 + i
    assert_hash(
      "two bytes",
      lead,
      hash_of(trace_shift_jis, pairs(lead)),
      expected,
    )
  }
  for i, expected in golden_shift_jis_after {
    let lead = 0x81 + i
    assert_hash(
      "two bytes and more",
      lead,
      hash_of(trace_shift_jis, after(lead)),
      expected,
    )
  }
}

///|
test "EUC-JP decoder answers like encoding_rs" {
  assert_eq(hash_of(trace_euc_jp, singles()), golden_euc_jp_single)
  for i, expected in golden_euc_jp_pairs {
    let lead = 0x81 + i
    assert_hash("two bytes", lead, hash_of(trace_euc_jp, pairs(lead)), expected)
  }
  for i, expected in golden_euc_jp_after {
    let lead = 0x81 + i
    assert_hash(
      "two bytes and more",
      lead,
      hash_of(trace_euc_jp, after(lead)),
      expected,
    )
  }
  for i, expected in golden_euc_jp_jis0212 {
    let lead = 0xA1 + i
    assert_hash(
      "JIS X 0212",
      lead,
      hash_of(trace_euc_jp, jis0212(lead)),
      expected,
    )
  }
}

///|
test "ISO-2022-JP decoder answers like encoding_rs" {
  assert_eq(hash_of(trace_iso_2022_jp, singles()), golden_iso_2022_jp_single)
  assert_eq(
    hash_of(trace_iso_2022_jp, iso_2022_jp_escapes()),
    golden_iso_2022_jp_escapes,
  )
  for i, expected in golden_iso_2022_jp_designations {
    assert_hash(
      "designation",
      i,
      hash_of(trace_iso_2022_jp, iso_2022_jp_after(designations[i])),
      expected,
    )
  }
  for i, expected in golden_iso_2022_jp_jis0208 {
    let lead = 0x21 + i
    assert_hash(
      "JIS X 0208",
      lead,
      hash_of(trace_iso_2022_jp, iso_2022_jp_jis0208(lead)),
      expected,
    )
  }
  assert_eq(
    hash_of(trace_iso_2022_jp, iso_2022_jp_sequences()),
    golden_iso_2022_jp_sequences,
  )
}

///|
fn steps(feed : (Int32) -> Step, bytes : Array[Int32]) -> Array[Step] {
  bytes.map(feed)
}

///|
test "Japanese examples" {
  // あ (U+3042) in Shift_JIS, EUC-JP and ISO-2022-JP
  let shift_jis = ShiftJisDecoder::new()
  assert_true(
    steps(b => shift_jis.feed(b), [0x82, 0xA0]) is [Pending, Unit(0x3042)],
  )
  let euc_jp = EucJpDecoder::new()
  assert_true(
    steps(b => euc_jp.feed(b), [0xA4, 0xA2]) is [Pending, Unit(0x3042)],
  )
  let iso = Iso2022JpDecoder::new()
  assert_true(
    steps(b => iso.feed(b), [0x1B, 0x24, 0x42, 0x24, 0x22])
    is [Pending, Pending, Pending, Pending, Unit(0x3042)],
  )
  // Half-width katakana ｱ
  let shift_jis = ShiftJisDecoder::new()
  assert_true(steps(b => shift_jis.feed(b), [0xB1]) is [Unit(0xFF71)])
  // Shift_JIS user-defined characters are in the Private Use Area.
  let shift_jis = ShiftJisDecoder::new()
  assert_true(steps(b => shift_jis.feed(b), [0xF0, 0x40]) is [_, Unit(0xE000)])
  // An escape sequence right after another is an error.
  let iso = Iso2022JpDecoder::new()
  assert_true(
    steps(b => iso.feed(b), [0x1B, 0x24, 0x42, 0x1B, 0x28, 0x42])
    is [_, _, Pending, _, _, Malformed(3)],
  )
  // So is ESC at the end of the stream.
  let iso = Iso2022JpDecoder::new()
  iso.feed(0x1B) |> ignore
  assert_true(iso.incomplete())
}
