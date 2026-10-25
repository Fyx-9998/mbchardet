// Compares Detector::score, Detector::scores and Detector::guess with what
// chardetng 1.0.0 computes for the inputs in golden_data_test.mbt, and
// Encoding::from_label with what encoding_rs 0.8.42 finds for those in
// golden_labels_test.mbt, both written by tools/golden.

///|
fn golden_encoding(name : String) -> @mbchardet.Encoding {
  for encoding in @mbchardet.Encoding::all() {
    if encoding.name() == name {
      return encoding
    }
  }
  abort("golden data names an unknown encoding: \{name}")
}

///|
fn parse_scores(scores : String) -> Array[Int64?] raise {
  let parsed = []
  for value in scores.split(" ") {
    parsed.push(
      if value == "-" {
        None
      } else {
        Some(@string.parse_int64(value))
      },
    )
  }
  parsed
}

///|
/// A new detector fed `input` whole, or in chunks of `chunk` bytes like
/// Rust's `slice::chunks`, marking the end on the final chunk if `last`.
fn fed(
  input : Bytes,
  chunk~ : Int32?,
  last~ : Bool,
  allow_iso_2022_jp~ : Bool = true,
) -> @mbchardet.Detector {
  let detector = @mbchardet.Detector::new(allow_iso_2022_jp~)
  match chunk {
    None => detector.feed(input[:], last~) |> ignore
    Some(size) => {
      let mut start = 0
      while input.length() - start > size {
        detector.feed(input[start:start + size]) |> ignore
        start += size
      }
      detector.feed(input[start:], last~) |> ignore
    }
  }
  detector
}

///|
fn scores_of(
  input : Bytes,
  encodings : Array[@mbchardet.Encoding],
  chunk~ : Int32?,
  last~ : Bool,
) -> Array[Int64?] {
  let detector = fed(input, chunk~, last~)
  encodings.map(encoding => detector.score(encoding))
}

///|
fn assert_scores(
  label : String,
  way : String,
  encodings : Array[@mbchardet.Encoding],
  actual : Array[Int64?],
  expected : String,
) -> Unit raise {
  let expected = parse_scores(expected)
  assert_eq(expected.length(), encodings.length())
  for i, encoding in encodings {
    if actual[i] != expected[i] {
      let show = (score : Int64?) => {
        match score {
          Some(s) => s.to_string()
          None => "ruled out"
        }
      }
      fail(
        "\{label}, \{way}: \{encoding} scores \{show(actual[i])}, chardetng \{show(expected[i])}",
      )
    }
  }
}

///|
/// Checks that `ranked`, from `Detector::scores`, lists the encodings that
/// `expected` does not rule out, with the same scores, highest first and in
/// the order of `Detector::encodings()` when equal.
fn assert_ranked(
  label : String,
  encodings : Array[@mbchardet.Encoding],
  ranked : Array[(@mbchardet.Encoding, Int64)],
  expected : String,
) -> Unit raise {
  let expected = parse_scores(expected)
  let pairs = []
  for i, encoding in encodings {
    if expected[i] is Some(score) {
      pairs.push((encoding, score))
    }
  }
  let shown = ranked.map(entry => "\{entry.0} \{entry.1}").join(", ")
  assert_eq(ranked.length(), pairs.length(), msg="\{label}: \{shown}")
  for pair in pairs {
    assert_true(
      ranked.contains(pair),
      msg="\{label}: \{pair.0} \{pair.1} not in \{shown}",
    )
  }
  let order = @mbchardet.Detector::encodings()
  let position = (encoding : @mbchardet.Encoding) => {
    order.search(encoding).unwrap()
  }
  for i in 1..<ranked.length() {
    let (before, high) = ranked[i - 1]
    let (after, low) = ranked[i]
    assert_true(
      high > low || (high == low && position(before) < position(after)),
      msg="\{label}: \{shown}",
    )
  }
}

///|
test "scores match chardetng 1.0.0" {
  let encodings = golden_encodings.map(golden_encoding)
  assert_eq(golden_cases.length(), 396)
  for case in golden_cases {
    let (label, input, whole, open, chunked) = case
    assert_scores(
      label,
      "whole",
      encodings,
      scores_of(input, encodings, chunk=None, last=true),
      whole,
    )
    assert_ranked(
      label,
      encodings,
      fed(input, chunk=None, last=true).scores(),
      whole,
    )
    assert_scores(
      label,
      "whole, end not marked",
      encodings,
      scores_of(input, encodings, chunk=None, last=false),
      open,
    )
    for size in [1, 2, 3, 7] {
      let mut expected = whole
      for entry in chunked {
        if entry.0 == size {
          expected = entry.1
        }
      }
      assert_scores(
        label,
        "in \{size}-byte chunks",
        encodings,
        scores_of(input, encodings, chunk=Some(size), last=true),
        expected,
      )
    }
  }
}

///|
/// The guesses for `input` in the order of golden_guesses, each with how it
/// was made.
fn guesses_of(input : Bytes) -> Array[(String, @mbchardet.Encoding)] {
  let guesses = []
  let detector = fed(input, chunk=None, last=true)
  for entry in golden_tlds {
    let tld = entry.0
    let domain = match tld {
      Some(label) => "TLD \"\{label}\""
      None => "no TLD"
    }
    guesses.push(("\{domain}, UTF-8 allowed", detector.guess(tld?)))
    guesses.push(
      ("\{domain}, UTF-8 denied", detector.guess(tld?, allow_utf8=false)),
    )
  }
  let denied = fed(input, chunk=None, last=true, allow_iso_2022_jp=false)
  guesses.push(("ISO-2022-JP denied", denied.guess()))
  guesses.push(("end not marked", fed(input, chunk=None, last=false).guess()))
  for size in [1, 2, 3, 7] {
    guesses.push(
      (
        "in \{size}-byte chunks",
        fed(input, chunk=Some(size), last=true).guess(),
      ),
    )
  }
  guesses
}

///|
test "guesses match chardetng 1.0.0" {
  let encodings = golden_encodings.map(golden_encoding)
  assert_eq(golden_tlds.length(), 34)
  assert_eq(golden_guesses.length(), golden_cases.length())
  for i, case in golden_cases {
    let (label, input, _, _, _) = case
    let (guess_label, letters) = golden_guesses[i]
    assert_eq(guess_label, label)
    let expected = letters
      .to_array()
      .map(c => encodings[c.to_int() - 'a'.to_int()])
    let actual = guesses_of(input)
    assert_eq(actual.length(), expected.length())
    for j, guess in actual {
      if guess.1 != expected[j] {
        fail("\{label}, \{guess.0}: guess \{guess.1}, chardetng \{expected[j]}")
      }
    }
  }
}

///|
test "tld_may_affect_guess matches chardetng 1.0.0" {
  for entry in golden_tlds {
    if entry.0 is Some(tld) {
      assert_eq(@mbchardet.tld_may_affect_guess(tld), entry.1)
    }
  }
}

///|
test "labels match encoding_rs 0.8.42" {
  assert_eq(golden_labels.length(), 1271)
  for case in golden_labels {
    let (input, expected) = case
    let found = @mbchardet.Encoding::from_label(input).map(e => e.name())
    if found != expected {
      let show = (name : String?) => name.unwrap_or("no encoding")
      fail(
        "label \{input.escape()}: \{show(found)}, encoding_rs \{show(expected)}",
      )
    }
  }
}
