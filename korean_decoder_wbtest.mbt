// Checks the EUC-KR decoder against encoding_rs 0.8.42, with the hashes
// tools/golden writes to golden_trace_wbtest.mbt. Fnv, record, hash_of,
// singles, pairs, after and assert_hash are in cjk_decoder_wbtest.mbt.

///|
/// EUC-KR goes on after a malformed sequence, as its candidate does.
fn trace_euc_kr(sequence : Array[Int32], hash : Fnv) -> Unit {
  let decoder = EucKrDecoder::new()
  for b in sequence {
    record(decoder.feed(b), hash) |> ignore
  }
  hash.word(2)
  hash.word(if decoder.incomplete() { 1 } else { 0 })
}

///|
test "EUC-KR decoder answers like encoding_rs" {
  assert_eq(hash_of(trace_euc_kr, singles()), golden_euc_kr_single)
  for i, expected in golden_euc_kr_pairs {
    let lead = 0x81 + i
    assert_hash("two bytes", lead, hash_of(trace_euc_kr, pairs(lead)), expected)
  }
  for i, expected in golden_euc_kr_after {
    let lead = 0x81 + i
    assert_hash(
      "two bytes and more",
      lead,
      hash_of(trace_euc_kr, after(lead)),
      expected,
    )
  }
}

///|
test "EUC-KR examples" {
  let decoder = EucKrDecoder::new()
  // 한 (U+D55C) in KS X 1001, and 똠 (U+B620) from the code page 949
  // extension below 0xA1.
  assert_true(
    [0xC7, 0xD1, 0x8C, 0x63].map(b => decoder.feed(b))
    is [Pending, Unit(0xD55C), Pending, Unit(0xB620)],
  )
  // CB D0 is the compatibility ideograph U+F900.
  assert_true([0xCB, 0xD0].map(b => decoder.feed(b)) is [Pending, Unit(0xF900)])
  // A1 7B has no character; 0x7B is ASCII, so the sequence is one byte.
  assert_true([0xA1, 0x7B].map(b => decoder.feed(b)) is [_, Malformed(1)])
  assert_true([0xC9, 0xA1].map(b => decoder.feed(b)) is [_, Malformed(2)])
  decoder.feed(0xC7) |> ignore
  assert_true(decoder.incomplete())
}
