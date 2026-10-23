// Compares prescan_html with the cases of html5lib-tests and
// web-platform-tests, and with what html-encoding-sniffer 7.0.0 finds for
// mutations of short documents: the inputs in prescan_data_test.mbt,
// written by tools/sniffer, varied as mutation_test.mbt describes.

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
test "the prescan matches html-encoding-sniffer 7.0.0" {
  let names = prescan_names.map(name => @mbchardet.Encoding::from_label(name))
  let mut total = 0
  for entry in prescan_seeds {
    let (seed, runs) = entry
    let answers = decode_runs(runs)
    let mutations = mutations(seed, prescan_alphabet)
    assert_eq(mutations.length(), answers.length())
    for i, mutation in mutations {
      let expected = match answers[i] {
        '-' => None
        c => names[name_index(c)]
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
