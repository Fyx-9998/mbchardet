// Compares Detector::score with the scores chardetng 1.0.0 computes for the
// inputs in golden_data_test.mbt, written by tools/golden.

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
/// Feeds `input` whole, or in chunks of `chunk` bytes like Rust's
/// `slice::chunks`, marking the end on the final chunk if `last`.
fn scores_of(
  input : Bytes,
  encodings : Array[@mbchardet.Encoding],
  chunk~ : Int32?,
  last~ : Bool,
) -> Array[Int64?] {
  let detector = @mbchardet.Detector::new()
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
test "scores match chardetng 1.0.0" {
  let encodings = golden_encodings.map(golden_encoding)
  assert_eq(golden_cases.length(), 262)
  for case in golden_cases {
    let (label, input, whole, open, chunked) = case
    assert_scores(
      label,
      "whole",
      encodings,
      scores_of(input, encodings, chunk=None, last=true),
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
