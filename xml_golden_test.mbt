// Compares sniff_xml with what expat finds in the XML declarations of
// mutations of short documents: the inputs in xml_data_test.mbt, written by
// tools/gen_xml_data.py, varied as mutation_test.mbt describes.

///|
fn show_sniffed(sniffed : @mbchardet.Sniffed) -> String {
  "\{sniffed.encoding} from \{@debug.to_string(sniffed.source)}"
}

///|
test "XML declarations are read as expat reads them" {
  let names = xml_names.map(name => {
    guard @mbchardet.Encoding::from_label(name) is Some(encoding) else {
      fail("\{name} is no label")
    }
    encoding
  })
  let mut total = 0
  for entry in xml_seeds {
    let (seed, runs) = entry
    let answers = decode_runs(runs)
    let mutations = mutations(seed, xml_alphabet)
    assert_eq(mutations.length(), answers.length())
    for i, mutation in mutations {
      let expected : @mbchardet.Sniffed = match answers[i] {
        '-' => { encoding: Utf8, source: Default, }
        c => { encoding: names[name_index(c)], source: XmlDeclaration, }
      }
      let found = @mbchardet.sniff_xml(mutation)
      if found != expected {
        fail(
          "\{bytes_literal(mutation)} (mutation \{i} of \{bytes_literal(seed)}): \{show_sniffed(found)}, expat \{show_sniffed(expected)}",
        )
      }
    }
    total += mutations.length()
  }
  assert_eq(xml_seeds.length(), 34)
  assert_eq(total, 61152)
}
