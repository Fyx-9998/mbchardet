// Benchmarks: detecting and decoding inputs of 256 KiB, run with
// `moon bench`. The inputs repeat sentences of the Tatoeba corpus as
// golden_data_test.mbt holds them encoded by encoding_rs (CC BY 2.0 FR, see
// NOTICE); `moon test` does not run these.

///|
/// The size each input reaches.
let bench_size : Int32 = 256 * 1024

///|
/// The corpus rows in `encoding` whose language is one of `languages`, or
/// any language if `languages` is empty, each followed by a space and
/// repeated until the input has `bench_size` bytes. Whole rows only, so no
/// character is cut.
fn bench_input(encoding : String, languages : Array[String]) -> Bytes {
  let sentences = []
  for case in golden_cases {
    // Corpus rows only: "<language> <Tatoeba ids> in <encoding>", not the
    // edge cases.
    guard case.0.strip_suffix(" in \{encoding}") is Some(rest) &&
      rest.find(" ") is Some(i) &&
      rest[i + 1:].iter().all(c => c is ('0'..<='9' | ',')) else {
      continue
    }
    if languages.is_empty() || languages.contains(rest[:i].to_owned()) {
      sentences.push(case.1)
    }
  }
  guard !sentences.is_empty() else {
    abort("no corpus sentence in \{encoding}")
  }
  let input = Buffer()
  while input.length() < bench_size {
    for sentence in sentences {
      input.write_bytes(sentence)
      input.write_byte(b' ')
      if input.length() >= bench_size {
        break
      }
    }
  }
  input.to_bytes()
}

///|
/// The inputs: (name, encoding, bytes).
fn bench_inputs() -> Array[(String, @mbchardet.Encoding, Bytes)] {
  let ascii = bench_input("UTF-8", ["en"])
  guard ascii.iter().all(b => b < 0x80) else { abort("not ASCII") }
  [
    ("UTF-8, 40 languages", Utf8, bench_input("UTF-8", [])),
    ("ASCII, English", Utf8, ascii),
    ("GBK, Chinese", Gbk, bench_input("GBK", ["zh", "yue"])),
    ("Shift_JIS, Japanese", ShiftJis, bench_input("Shift_JIS", ["ja"])),
    ("windows-1251, Cyrillic", Windows1251, bench_input("windows-1251", [])),
    (
      "windows-1252, Western European",
      Windows1252,
      bench_input("windows-1252", ["ca", "et", "is", "it", "pt"]),
    ),
  ]
}

///|
test "bench detect UTF-8" (it : @bench.T) {
  bench_detect(it, 0)
}

///|
test "bench detect ASCII" (it : @bench.T) {
  bench_detect(it, 1)
}

///|
test "bench detect GBK" (it : @bench.T) {
  bench_detect(it, 2)
}

///|
test "bench detect Shift_JIS" (it : @bench.T) {
  bench_detect(it, 3)
}

///|
test "bench detect windows-1251" (it : @bench.T) {
  bench_detect(it, 4)
}

///|
test "bench detect windows-1252" (it : @bench.T) {
  bench_detect(it, 5)
}

///|
/// Feeds input `index` to a new detector whole and guesses.
fn bench_detect(it : @bench.T, index : Int32) -> Unit {
  let (_, encoding, input) = bench_inputs()[index]
  let guess = () => {
    let detector = @mbchardet.Detector::new()
    detector.feed(input[:], last=true) |> ignore
    detector.guess()
  }
  // The benchmark measures a correct guess.
  guard guess() == encoding else { abort("wrong guess for input \{index}") }
  it.bench(fn() { it.keep(guess()) })
}

///|
test "bench check_utf8" (it : @bench.T) {
  let (_, _, input) = bench_inputs()[0]
  it.bench(fn() { it.keep(@mbchardet.check_utf8(input[:])) })
}

///|
test "bench decode UTF-8" (it : @bench.T) {
  bench_decode(it, 0)
}

///|
test "bench decode GBK" (it : @bench.T) {
  bench_decode(it, 2)
}

///|
test "bench decode Shift_JIS" (it : @bench.T) {
  bench_decode(it, 3)
}

///|
test "bench decode windows-1251" (it : @bench.T) {
  bench_decode(it, 4)
}

///|
/// Decodes input `index` with Encoding::decode.
fn bench_decode(it : @bench.T, index : Int32) -> Unit {
  let (_, encoding, input) = bench_inputs()[index]
  guard encoding.decode(input[:]) is Ok(_) else { abort("not decoded") }
  it.bench(fn() { it.keep(encoding.decode(input[:])) })
}

///|
test "bench Decoder UTF-8 in 64 KiB chunks" (it : @bench.T) {
  bench_decoder(it, 0)
}

///|
test "bench Decoder GBK in 64 KiB chunks" (it : @bench.T) {
  bench_decoder(it, 2)
}

///|
/// Decodes input `index` with a Decoder in chunks of 64 KiB.
fn bench_decoder(it : @bench.T, index : Int32) -> Unit {
  let (_, encoding, input) = bench_inputs()[index]
  let decode = () => {
    let decoder = @mbchardet.Decoder::new(encoding)
    let text = StringBuilder()
    let mut start = 0
    while start < input.length() {
      let end = if input.length() - start > 65536 {
        start + 65536
      } else {
        input.length()
      }
      if decoder.decode(input[start:end]) is Ok(part) {
        text.write_string(part)
      }
      start = end
    }
    decoder.finish() |> ignore
    text.to_string()
  }
  guard decode() == encoding.decode(input[:]).unwrap() else {
    abort("Decoder and decode differ")
  }
  it.bench(fn() { it.keep(decode()) })
}
