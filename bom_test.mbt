///|
test "each byte order mark" {
  assert_eq(
    @mbchardet.sniff_bom(b"\xEF\xBB\xBFhello"[:]),
    Some((@mbchardet.Utf8, 3)),
  )
  assert_eq(
    @mbchardet.sniff_bom(b"\xFE\xFF\x00h"[:]),
    Some((@mbchardet.Utf16Be, 2)),
  )
  assert_eq(
    @mbchardet.sniff_bom(b"\xFF\xFEh\x00"[:]),
    Some((@mbchardet.Utf16Le, 2)),
  )
}

///|
test "a mark with nothing after it" {
  assert_eq(
    @mbchardet.sniff_bom(b"\xEF\xBB\xBF"[:]),
    Some((@mbchardet.Utf8, 3)),
  )
  assert_eq(@mbchardet.sniff_bom(b"\xFE\xFF"[:]), Some((@mbchardet.Utf16Be, 2)))
  assert_eq(@mbchardet.sniff_bom(b"\xFF\xFE"[:]), Some((@mbchardet.Utf16Le, 2)))
}

///|
test "no mark" {
  assert_eq(@mbchardet.sniff_bom(b""[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"hello"[:]), None)
  // Truncated marks.
  assert_eq(@mbchardet.sniff_bom(b"\xEF"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\xEF\xBB"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\xFE"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\xFF"[:]), None)
  // Near misses.
  assert_eq(@mbchardet.sniff_bom(b"\xEF\xBB\xBE"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\xEF\xBF\xBB"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\xFE\xFE"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\xFF\xFF"[:]), None)
  // A mark that is not at the start does not count.
  assert_eq(@mbchardet.sniff_bom(b" \xEF\xBB\xBF"[:]), None)
  assert_eq(@mbchardet.sniff_bom(b"\x00\xFE\xFF"[:]), None)
}

///|
test "the first matching mark wins" {
  assert_eq(
    @mbchardet.sniff_bom(b"\xEF\xBB\xBF\xFE\xFF"[:]),
    Some((@mbchardet.Utf8, 3)),
  )
  assert_eq(
    @mbchardet.sniff_bom(b"\xFF\xFE\xFF\xFE"[:]),
    Some((@mbchardet.Utf16Le, 2)),
  )
}

///|
test "UTF-32 marks follow the Encoding Standard" {
  // FF FE 00 00 is the UTF-32LE mark, but the standard only looks at the
  // first two bytes and selects UTF-16LE.
  assert_eq(
    @mbchardet.sniff_bom(b"\xFF\xFE\x00\x00"[:]),
    Some((@mbchardet.Utf16Le, 2)),
  )
  // 00 00 FE FF, the UTF-32BE mark, is not a mark the standard knows.
  assert_eq(@mbchardet.sniff_bom(b"\x00\x00\xFE\xFF"[:]), None)
}

///|
test "views that do not start at offset zero" {
  let data = b"ab\xFE\xFFcd"
  assert_eq(@mbchardet.sniff_bom(data[2:]), Some((@mbchardet.Utf16Be, 2)))
  assert_eq(@mbchardet.sniff_bom(data[1:]), None)
  // The view ends inside the mark.
  assert_eq(@mbchardet.sniff_bom(data[2:3]), None)
}
