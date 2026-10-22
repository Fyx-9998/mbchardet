///|
test "canonical names" {
  assert_eq(@mbchardet.Utf8.name(), "UTF-8")
  assert_eq(@mbchardet.Utf16Be.name(), "UTF-16BE")
  assert_eq(@mbchardet.Utf16Le.name(), "UTF-16LE")
  assert_eq(@mbchardet.Gbk.name(), "GBK")
  assert_eq(@mbchardet.Big5.name(), "Big5")
  assert_eq(@mbchardet.Windows874.name(), "windows-874")
  assert_eq(@mbchardet.Windows1251.name(), "windows-1251")
  assert_eq(@mbchardet.Iso8859_13.name(), "ISO-8859-13")
  assert_eq(@mbchardet.Koi8U.name(), "KOI8-U")
  assert_eq(@mbchardet.Ibm866.name(), "IBM866")
}

///|
test "every encoding has its own name" {
  let all = @mbchardet.Encoding::all()
  assert_eq(all.length(), 24)
  let names : Set[String] = Set([])
  for encoding in all {
    assert_false(names.contains(encoding.name()))
    names.add(encoding.name())
  }
}

///|
test "show writes the canonical name" {
  for enc in @mbchardet.Encoding::all() {
    assert_eq(enc.to_string(), enc.name())
    assert_eq("\{enc}", enc.name())
  }
}
