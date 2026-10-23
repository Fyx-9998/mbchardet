///|
test "canonical names" {
  assert_eq(@mbchardet.Utf8.name(), "UTF-8")
  assert_eq(@mbchardet.Utf16Be.name(), "UTF-16BE")
  assert_eq(@mbchardet.Utf16Le.name(), "UTF-16LE")
  assert_eq(@mbchardet.Gbk.name(), "GBK")
  assert_eq(@mbchardet.Big5.name(), "Big5")
  assert_eq(@mbchardet.ShiftJis.name(), "Shift_JIS")
  assert_eq(@mbchardet.EucJp.name(), "EUC-JP")
  assert_eq(@mbchardet.Iso2022Jp.name(), "ISO-2022-JP")
  assert_eq(@mbchardet.EucKr.name(), "EUC-KR")
  assert_eq(@mbchardet.Windows874.name(), "windows-874")
  assert_eq(@mbchardet.Windows1251.name(), "windows-1251")
  assert_eq(@mbchardet.Iso8859_13.name(), "ISO-8859-13")
  assert_eq(@mbchardet.Koi8U.name(), "KOI8-U")
  assert_eq(@mbchardet.Ibm866.name(), "IBM866")
  assert_eq(@mbchardet.Iso8859_8I.name(), "ISO-8859-8-I")
  assert_eq(@mbchardet.Macintosh.name(), "macintosh")
  assert_eq(@mbchardet.XMacCyrillic.name(), "x-mac-cyrillic")
  assert_eq(@mbchardet.Gb18030.name(), "gb18030")
  assert_eq(@mbchardet.Replacement.name(), "replacement")
  assert_eq(@mbchardet.XUserDefined.name(), "x-user-defined")
}

///|
test "every encoding has its own name" {
  let all = @mbchardet.Encoding::all()
  assert_eq(all.length(), 40)
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

///|
test "every name is a label" {
  for enc in @mbchardet.Encoding::all() {
    assert_eq(@mbchardet.Encoding::from_label(enc.name()), Some(enc))
    assert_eq(@mbchardet.Encoding::from_label(enc.name().to_upper()), Some(enc))
  }
}

///|
test "labels" {
  assert_eq(@mbchardet.Encoding::from_label("utf8"), Some(@mbchardet.Utf8))
  assert_eq(
    @mbchardet.Encoding::from_label("latin1"),
    Some(@mbchardet.Windows1252),
  )
  assert_eq(
    @mbchardet.Encoding::from_label("ascii"),
    Some(@mbchardet.Windows1252),
  )
  assert_eq(
    @mbchardet.Encoding::from_label("iso-8859-9"),
    Some(@mbchardet.Windows1254),
  )
  assert_eq(@mbchardet.Encoding::from_label("gb2312"), Some(@mbchardet.Gbk))
  assert_eq(
    @mbchardet.Encoding::from_label("x-sjis"),
    Some(@mbchardet.ShiftJis),
  )
  assert_eq(@mbchardet.Encoding::from_label("utf-16"), Some(@mbchardet.Utf16Le))
  assert_eq(
    @mbchardet.Encoding::from_label("iso-2022-kr"),
    Some(@mbchardet.Replacement),
  )
  assert_eq(@mbchardet.Encoding::from_label("utf-7"), None)
  assert_eq(@mbchardet.Encoding::from_label("utf-32"), None)
  assert_eq(@mbchardet.Encoding::from_label(""), None)
  assert_eq(@mbchardet.Encoding::from_label("utf 8"), None)
}

///|
test "labels ignore ASCII whitespace around them and ASCII case" {
  assert_eq(
    @mbchardet.Encoding::from_label("\t\n\u{0C}\r Shift_JIS \r\u{0C}\n\t"),
    Some(@mbchardet.ShiftJis),
  )
  assert_eq(@mbchardet.Encoding::from_label("  EUC-kr"), Some(@mbchardet.EucKr))
  // Vertical tab and no-break space are not ASCII whitespace.
  assert_eq(@mbchardet.Encoding::from_label("\u{0B}utf-8"), None)
  assert_eq(@mbchardet.Encoding::from_label("utf-8\u{A0}"), None)
  // Nor is the Kelvin sign an ASCII K, though Unicode lowercases it to k.
  assert_eq(@mbchardet.Encoding::from_label("\u{212A}oi8-r"), None)
  assert_eq(@mbchardet.Encoding::from_label("koi8-r"), Some(@mbchardet.Koi8R))
}
