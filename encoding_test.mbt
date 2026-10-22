///|
test "canonical names" {
  assert_eq(@mbchardet.Utf8.name(), "UTF-8")
  assert_eq(@mbchardet.Utf16Be.name(), "UTF-16BE")
  assert_eq(@mbchardet.Utf16Le.name(), "UTF-16LE")
}

///|
test "show writes the canonical name" {
  for enc in [@mbchardet.Utf8, @mbchardet.Utf16Be, @mbchardet.Utf16Le] {
    assert_eq(enc.to_string(), enc.name())
    assert_eq("\{enc}", enc.name())
  }
}
