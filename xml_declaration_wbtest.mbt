///|
/// What `xml_declaration` finds in `document`, with the encoding name as a
/// string.
fn declared(document : Bytes) -> String?? {
  match xml_declaration(document[:]) {
    Some(Some(name)) => Some(Some(isomorphic_decode(name)))
    Some(None) => Some(None)
    None => None
  }
}

///|
test "a declaration with and without an encoding" {
  assert_eq(declared(b"<?xml version=\"1.0\"?>"), Some(None))
  assert_eq(
    declared(b"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"),
    Some(Some("UTF-8")),
  )
  assert_eq(
    declared(b"<?xml version='1.0' encoding='Shift_JIS' standalone='no'?>"),
    Some(Some("Shift_JIS")),
  )
  assert_eq(declared(b"<?xml version=\"1.0\" standalone=\"yes\"?>"), Some(None))
  // The quotes of each value can differ.
  assert_eq(
    declared(b"<?xml version='1.0' encoding=\"koi8-r\" standalone='yes'?>"),
    Some(Some("koi8-r")),
  )
  // What follows the declaration does not matter.
  assert_eq(
    declared(b"<?xml version=\"1.0\" encoding=\"gbk\"?><r>\xC4\xE3</r>"),
    Some(Some("gbk")),
  )
}

///|
test "white space in a declaration" {
  assert_eq(
    declared(b"<?xml\tversion = \"1.0\"\r\nencoding\t=\t\"big5\"\n?>"),
    Some(Some("big5")),
  )
  assert_eq(
    declared(b"<?xml  version='1.0'  encoding='cp1250'  ?>"),
    Some(Some("cp1250")),
  )
  // White space is space, tab, carriage return and line feed only.
  assert_eq(declared(b"<?xml\x0Cversion=\"1.0\"?>"), None)
  assert_eq(declared(b"<?xml\xA0version=\"1.0\"?>"), None)
  assert_eq(declared(b"<?xml version=\"1.0\"\x0Cencoding=\"gbk\"?>"), None)
  // It is needed after "<?xml" and between the parts.
  assert_eq(declared(b"<?xmlversion=\"1.0\"?>"), None)
  assert_eq(declared(b"<?xml version=\"1.0\"encoding=\"gbk\"?>"), None)
  assert_eq(
    declared(b"<?xml version=\"1.0\" encoding=\"gbk\"standalone=\"no\"?>"),
    None,
  )
  // But not before "?>", which cannot be split.
  assert_eq(declared(b"<?xml version=\"1.0\"?>"), Some(None))
  assert_eq(declared(b"<?xml version=\"1.0\"? >"), None)
}

///|
test "the version number" {
  for version in ["1.0", "1.1", "1.10", "1.234"] {
    assert_eq(
      declared(@utf8.encode("<?xml version=\"\{version}\" encoding=\"gbk\"?>")),
      Some(Some("gbk")),
    )
  }
  for version in ["", "1", "1.", "2.0", "1.0a", "01.0", "1.x", " 1.0"] {
    assert_eq(
      declared(@utf8.encode("<?xml version=\"\{version}\" encoding=\"gbk\"?>")),
      None,
    )
  }
  // It is required.
  assert_eq(declared(b"<?xml encoding=\"gbk\"?>"), None)
  assert_eq(declared(b"<?xml?>"), None)
}

///|
test "the encoding name" {
  for name in ["a", "Z", "A.b_c-9", "x-user-defined", "ISO_8859-1"] {
    assert_eq(
      declared(@utf8.encode("<?xml version=\"1.0\" encoding=\"\{name}\"?>")),
      Some(Some(name)),
    )
  }
  for name in ["", "1252", "-x", "_x", ".x", "lat in1", "utf-8 ", "utf:8", "é"] {
    assert_eq(
      declared(@utf8.encode("<?xml version=\"1.0\" encoding=\"\{name}\"?>")),
      None,
    )
  }
}

///|
test "the standalone declaration" {
  for value in ["Yes", "true", "", "maybe"] {
    assert_eq(
      declared(@utf8.encode("<?xml version=\"1.0\" standalone=\"\{value}\"?>")),
      None,
    )
  }
  // It comes last, and each part comes once.
  assert_eq(
    declared(b"<?xml version=\"1.0\" standalone=\"no\" encoding=\"gbk\"?>"),
    None,
  )
  assert_eq(
    declared(b"<?xml version=\"1.0\" encoding=\"gbk\" encoding=\"big5\"?>"),
    None,
  )
  assert_eq(declared(b"<?xml encoding=\"gbk\" version=\"1.0\"?>"), None)
}

///|
test "quotes" {
  assert_eq(declared(b"<?xml version=\"1.0' encoding=\"gbk\"?>"), None)
  assert_eq(declared(b"<?xml version=\"1.0\" encoding='gbk\"?>"), None)
  assert_eq(declared(b"<?xml version=1.0 encoding=gbk?>"), None)
}

///|
test "no declaration" {
  assert_eq(declared(b""), None)
  assert_eq(declared(b"<r/>"), None)
  // Names are case-sensitive.
  assert_eq(declared(b"<?XML version=\"1.0\"?>"), None)
  assert_eq(declared(b"<?xml Version=\"1.0\"?>"), None)
  assert_eq(declared(b"<?xml version=\"1.0\" Encoding=\"gbk\"?>"), None)
  // A processing instruction whose target starts with "xml".
  assert_eq(declared(b"<?xml-stylesheet href=\"s.xsl\"?>"), None)
  // The declaration has to come first.
  assert_eq(declared(b" <?xml version=\"1.0\"?>"), None)
  assert_eq(declared(b"\n<?xml version=\"1.0\"?>"), None)
  // Truncated declarations.
  let full = b"<?xml version=\"1.0\" encoding=\"gbk\" standalone=\"no\" ?>"
  for length in 0..<full.length() {
    assert_eq(declared(full[:length].to_owned()), None)
  }
  assert_eq(declared(full), Some(Some("gbk")))
}
