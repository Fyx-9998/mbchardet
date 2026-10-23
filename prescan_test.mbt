///|
fn prescan(html : String, limit? : Int32) -> @mbchardet.Encoding? {
  @mbchardet.prescan_html(@utf8.encode(html)[:], limit?)
}

///|
test "meta charset" {
  assert_eq(prescan("<meta charset=\"utf-8\">"), Some(@mbchardet.Utf8))
  assert_eq(prescan("<meta charset='koi8-r'>"), Some(@mbchardet.Koi8R))
  assert_eq(prescan("<META CHARSET=Shift_JIS>"), Some(@mbchardet.ShiftJis))
  assert_eq(prescan("<meta/charset=gbk>"), Some(@mbchardet.Gbk))
  assert_eq(
    prescan("<!doctype html><html><head><meta charset=big5></head>"),
    Some(@mbchardet.Big5),
  )
  assert_eq(prescan("<meta\n  charset = \"euc-kr\"\n>"), Some(@mbchardet.EucKr))
  // A label is looked up as the Encoding Standard says.
  assert_eq(prescan("<meta charset=latin1>"), Some(@mbchardet.Windows1252))
  assert_eq(
    prescan("<meta charset=\" iso-8859-2 \">"),
    Some(@mbchardet.Iso8859_2),
  )
}

///|
test "meta http-equiv and content" {
  let declared = Some(@mbchardet.Windows1251)
  assert_eq(
    prescan(
      "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1251\">",
    ),
    declared,
  )
  assert_eq(
    prescan(
      "<meta content='text/html; charset=windows-1251' http-equiv='content-type'>",
    ),
    declared,
  )
  // Without the pragma, content declares nothing.
  assert_eq(prescan("<meta content=\"text/html; charset=windows-1251\">"), None)
  assert_eq(
    prescan(
      "<meta http-equiv=\"Content-Type \" content=\"text/html; charset=windows-1251\">",
    ),
    None,
  )
  // charset needs no pragma.
  assert_eq(
    prescan(
      "<meta http-equiv=\"refresh\" content=\"5\" charset=\"windows-1251\">",
    ),
    declared,
  )
}

///|
test "the charset in a content attribute" {
  fn content(value : String) -> @mbchardet.Encoding? {
    prescan("<meta http-equiv=content-type content=\"\{value}\">")
  }

  assert_eq(content("charset=utf-8"), Some(@mbchardet.Utf8))
  assert_eq(content("text/html;charset = 'utf-8'"), Some(@mbchardet.Utf8))
  assert_eq(content("text/html; CHARSET=utf-8; x"), Some(@mbchardet.Utf8))
  assert_eq(content("text/html;\tcharset=utf-8 foo"), Some(@mbchardet.Utf8))
  // A "charset" without "=" is skipped.
  assert_eq(content("charsets; charset=utf-8"), Some(@mbchardet.Utf8))
  assert_eq(content("charset charset=utf-8"), Some(@mbchardet.Utf8))
  // An unmatched quote, or nothing after "=", declares nothing.
  assert_eq(content("charset='utf-8"), None)
  assert_eq(content("charset="), None)
  assert_eq(content("charset=  "), None)
  assert_eq(content("text/html"), None)
  // Only the first "charset=" counts.
  assert_eq(content("charset=bogus; charset=utf-8"), None)
}

///|
test "the first declaration wins" {
  assert_eq(
    prescan("<meta charset=koi8-r><meta charset=utf-8>"),
    Some(@mbchardet.Koi8R),
  )
  // So does the first of the same attribute.
  assert_eq(
    prescan("<meta charset=koi8-r charset=utf-8>"),
    Some(@mbchardet.Koi8R),
  )
  assert_eq(
    prescan(
      "<meta http-equiv=refresh http-equiv=content-type content=\"charset=utf-8\">",
    ),
    None,
  )
  // A charset attribute replaces what content gave.
  assert_eq(
    prescan(
      "<meta http-equiv=content-type content=\"charset=utf-8\" charset=koi8-r>",
    ),
    Some(@mbchardet.Koi8R),
  )
  // A meta that declares nothing usable is passed over.
  assert_eq(
    prescan("<meta charset=bogus><meta charset=utf-8>"),
    Some(@mbchardet.Utf8),
  )
}

///|
test "a charset of no encoding stops content from counting" {
  // charset is no longer null once a label of no encoding was seen, so
  // content does not set it. html-encoding-sniffer 7.0.0 takes no encoding
  // as null here and gives UTF-8.
  assert_eq(
    prescan(
      "<meta charset=\"bogus\" http-equiv=\"content-type\" content=\"text/html; charset=utf-8\">",
    ),
    None,
  )
  assert_eq(
    prescan(
      "<meta charset=bogus http-equiv=content-type content=\"charset=utf-8\"><meta charset=koi8-r>",
    ),
    Some(@mbchardet.Koi8R),
  )
}

///|
test "UTF-16 and x-user-defined in a meta" {
  assert_eq(prescan("<meta charset=utf-16>"), Some(@mbchardet.Utf8))
  assert_eq(prescan("<meta charset=utf-16be>"), Some(@mbchardet.Utf8))
  assert_eq(
    prescan("<meta charset=x-user-defined>"),
    Some(@mbchardet.Windows1252),
  )
  assert_eq(prescan("<meta charset=iso-2022-kr>"), Some(@mbchardet.Replacement))
}

///|
test "comments" {
  assert_eq(prescan("<!--<meta charset=utf-8>-->"), None)
  assert_eq(
    prescan("<!-- a -- b --><meta charset=utf-8>"),
    Some(@mbchardet.Utf8),
  )
  // The "--" that ends a comment may be the one that starts it.
  assert_eq(prescan("<!--><meta charset=utf-8>"), Some(@mbchardet.Utf8))
  assert_eq(prescan("<!---><meta charset=utf-8>"), Some(@mbchardet.Utf8))
  assert_eq(prescan("<!-- -><meta charset=utf-8>"), None)
}

///|
test "other tags" {
  // Inside an attribute of another tag.
  assert_eq(prescan("<p title=\"<meta charset=utf-8>\">"), None)
  assert_eq(
    prescan("<p title=\">\"><meta charset=utf-8>"),
    Some(@mbchardet.Utf8),
  )
  // Inside a tag of its own name.
  assert_eq(prescan("<metacharset=utf-8>"), None)
  assert_eq(prescan("<meta><meta charset=utf-8>"), Some(@mbchardet.Utf8))
  // Inside the content of an element, which the prescan does not know.
  assert_eq(
    prescan("<script>x = '<meta charset=utf-8>'</script>"),
    Some(@mbchardet.Utf8),
  )
  // `<!`, `</` and `<?` that are not followed by a letter end at the first
  // `>`, even inside quotes.
  assert_eq(prescan("<!x \">\"<meta charset=utf-8>"), Some(@mbchardet.Utf8))
  assert_eq(prescan("<?x \">\"<meta charset=utf-8>"), Some(@mbchardet.Utf8))
  assert_eq(prescan("</ \">\"<meta charset=utf-8>"), Some(@mbchardet.Utf8))
  // An end tag has attributes like a start tag. html-encoding-sniffer 7.0.0
  // ends it at the first `>` and gives UTF-8.
  assert_eq(prescan("</p title=\">\" <meta charset=utf-8>"), None)
  assert_eq(
    prescan("</p title=\">\"><meta charset=utf-8>"),
    Some(@mbchardet.Utf8),
  )
}

///|
test "running out of bytes" {
  assert_eq(prescan("<meta charset=utf-8"), None)
  assert_eq(prescan("<meta charset=\"utf-8\""), None)
  assert_eq(prescan("<meta charset=\"utf-8>"), None)
  assert_eq(prescan("<!-- <meta charset=utf-8>"), None)
  assert_eq(prescan("<p title=\"<meta charset=utf-8>"), None)
}

///|
test "the limit" {
  let html = "<meta charset=utf-8>"
  assert_eq(prescan(html, limit=20), Some(@mbchardet.Utf8))
  assert_eq(prescan(html, limit=19), None)
  assert_eq(prescan(html, limit=0), None)
  let padded = " ".repeat(1004) + html
  assert_eq(prescan(padded), Some(@mbchardet.Utf8))
  assert_eq(prescan(" " + padded), None)
  assert_eq(prescan(" " + padded, limit=1025), Some(@mbchardet.Utf8))
}

///|
test "panic on a negative limit" {
  prescan("<meta charset=utf-8>", limit=-1) |> ignore
}

///|
test "whitespace is ASCII whitespace" {
  // Vertical tab and no-break space separate nothing.
  assert_eq(prescan("<meta\u{0B}charset=utf-8>"), None)
  assert_eq(@mbchardet.prescan_html(b"<meta\xA0charset=utf-8>"[:]), None)
  assert_eq(
    @mbchardet.prescan_html(b"<meta \xA0charset=utf-8 \xA0charset=koi8-r>"[:]),
    None,
  )
  assert_eq(
    @mbchardet.prescan_html(b"<meta\x0Ccharset=utf-8>"[:]),
    Some(@mbchardet.Utf8),
  )
}

///|
test "UTF-16 XML declarations" {
  assert_eq(
    @mbchardet.prescan_html(b"<\x00?\x00x\x00"[:]),
    Some(@mbchardet.Utf16Le),
  )
  assert_eq(
    @mbchardet.prescan_html(b"\x00<\x00?\x00x"[:]),
    Some(@mbchardet.Utf16Be),
  )
  // The name is not checked, and UTF-16 wins over a meta.
  assert_eq(
    @mbchardet.prescan_html(b"<\x00?\x00x\x00<meta charset=utf-8>"[:]),
    Some(@mbchardet.Utf16Le),
  )
  assert_eq(
    @mbchardet.prescan_html(b"<\x00?\x00x<meta charset=utf-8>"[:]),
    Some(@mbchardet.Utf8),
  )
  assert_eq(@mbchardet.prescan_html(b"<\x00?\x00"[:]), None)
  // Even when the limit is smaller.
  assert_eq(
    @mbchardet.prescan_html(b"<\x00?\x00x\x00"[:], limit=0),
    Some(@mbchardet.Utf16Le),
  )
}

///|
test "XML declarations" {
  assert_eq(
    prescan("<?xml version=\"1.0\" encoding=\"windows-1251\"?>"),
    Some(@mbchardet.Windows1251),
  )
  assert_eq(
    prescan("<?xml version='1.0' encoding = 'koi8-r' ?>"),
    Some(@mbchardet.Koi8R),
  )
  assert_eq(prescan("<?xmlencoding=\"koi8-r\">"), Some(@mbchardet.Koi8R))
  // Every control character counts as space around "=".
  assert_eq(
    @mbchardet.prescan_html(b"<?xml encoding\x01=\x00'koi8-r'?>"[:]),
    Some(@mbchardet.Koi8R),
  )
  // The first "encoding", even inside another name.
  assert_eq(prescan("<?xml myencoding=\"koi8-r\"?>"), Some(@mbchardet.Koi8R))
  assert_eq(prescan("<?xml encodings=\"koi8-r\"?>"), None)
  // Matched case-sensitively, at the very start.
  assert_eq(prescan("<?XML encoding=\"koi8-r\"?>"), None)
  assert_eq(prescan("<?Xml encoding=\"koi8-r\"?>"), None)
  assert_eq(prescan("<?xmL encoding=\"koi8-r\"?>"), None)
  assert_eq(prescan("<?xml ENCODING=\"koi8-r\"?>"), None)
  assert_eq(prescan(" <?xml encoding=\"koi8-r\"?>"), None)
  // The label must be quoted, without spaces.
  assert_eq(prescan("<?xml encoding=koi8-r?>"), None)
  assert_eq(prescan("<?xml encoding=\" koi8-r\"?>"), None)
  assert_eq(prescan("<?xml encoding=\"koi8-r'?>"), None)
  // "encoding" must come before the first `>`, but the label need not.
  assert_eq(prescan("<?xml>encoding=\"koi8-r\"?>"), None)
  assert_eq(prescan("<?xml encoding=\"koi8>-r\"?>"), None)
  // UTF-16 is taken as UTF-8, but x-user-defined stays.
  assert_eq(prescan("<?xml encoding=\"utf-16\"?>"), Some(@mbchardet.Utf8))
  assert_eq(
    prescan("<?xml encoding=\"x-user-defined\"?>"),
    Some(@mbchardet.XUserDefined),
  )
  assert_eq(
    prescan("<?xml encoding=\"iso-2022-kr\"?>"),
    Some(@mbchardet.Replacement),
  )
}

///|
test "XML declarations and meta" {
  // A meta wins over an XML declaration.
  assert_eq(
    prescan("<?xml encoding=\"koi8-r\"?><meta charset=windows-1253>"),
    Some(@mbchardet.Windows1253),
  )
  // But not one inside the XML declaration, which ends at the first `>`.
  assert_eq(
    prescan("<?xml <meta charset=windows-1253 encoding=\"koi8-r\"?>"),
    Some(@mbchardet.Koi8R),
  )
  // The XML declaration may go past the limit.
  let long = "<?xml encoding=\"koi8-r\"" + " ".repeat(2000) + "?>"
  assert_eq(prescan(long), Some(@mbchardet.Koi8R))
  assert_eq(prescan(long, limit=0), Some(@mbchardet.Koi8R))
}
