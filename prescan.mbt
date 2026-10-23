// The prescan of the HTML Standard, as published on 2026-10-22: "prescan a
// byte stream to determine its encoding", "get an attribute" and "get an
// XML encoding" in section 13.2.3.2
// (https://html.spec.whatwg.org/multipage/parsing.html#determining-the-character-encoding),
// and "the algorithm for extracting a character encoding from a meta
// element" in section 2.5.3
// (https://html.spec.whatwg.org/multipage/urls-and-fetching.html#algorithm-for-extracting-a-character-encoding-from-a-meta-element).
// Quoted names in the comments are those of the steps.

///|
/// Looks for the encoding the start of an HTML document declares, with the
/// prescan of the HTML Standard
/// (<https://html.spec.whatwg.org/multipage/parsing.html#prescan-a-byte-stream-to-determine-its-encoding>),
/// which browsers run before they parse a document that has no byte order
/// mark and no encoding from the transport layer. The first of these
/// decides:
///
/// - `bytes` starts with `<?x` in UTF-16LE or UTF-16BE: that encoding.
/// - The first `<meta>` within the first `limit` bytes that declares an
///   encoding, as `<meta charset="...">` or as
///   `<meta http-equiv="Content-Type" content="...; charset=...">`.
///   Declarations inside comments and inside the attributes of other tags
///   do not count, and neither do labels the standard does not define. As
///   the standard requires, a declared UTF-16 is taken as UTF-8 and
///   x-user-defined as windows-1252.
/// - An XML declaration at the very start of `bytes`, such as
///   `<?xml version="1.0" encoding="windows-1251"?>`, looked for in all of
///   `bytes`, even past `limit`. A declared UTF-16 is taken as UTF-8.
///
/// Returns `None` when none of them applies. The standard leaves the number
/// of bytes to look at to the user agent and encourages 1024, the default
/// of `limit`; a conforming document declares its encoding within them.
///
/// Panics if `limit` is negative.
pub fn prescan_html(bytes : BytesView, limit~ : Int32 = 1024) -> Encoding? {
  if limit < 0 {
    abort("prescan_html: limit must not be negative, got \{limit}")
  }
  // "Prescan for UTF-16 XML declarations"
  match bytes {
    [0x3C, 0x00, 0x3F, 0x00, 0x78, 0x00, ..] => return Some(Utf16Le)
    [0x00, 0x3C, 0x00, 0x3F, 0x00, 0x78, ..] => return Some(Utf16Be)
    _ => ()
  }
  let end = if limit < bytes.length() { limit } else { bytes.length() }
  let scanner = Scanner::{ bytes: bytes[:end], pos: 0, }
  // Running out of bytes, or reaching `limit`, aborts the prescan, which
  // then returns what "get an XML encoding" finds in the same bytes.
  Some(scanner.meta_encoding()) catch {
    OutOfBytes => xml_encoding(bytes)
  }
}

///|
/// The prescan has run out of bytes.
priv suberror OutOfBytes

///|
/// A position in the bytes the loop of the prescan looks at.
priv struct Scanner {
  bytes : BytesView
  mut pos : Int32
}

///|
/// The byte at the position, if there is one.
fn Scanner::byte(self : Scanner) -> Byte raise OutOfBytes {
  if self.pos >= self.bytes.length() {
    raise OutOfBytes
  }
  self.bytes[self.pos]
}

///|
/// Moves the position to the next byte that `stop` accepts.
fn Scanner::skip_until(
  self : Scanner,
  stop : (Byte) -> Bool,
) -> Unit raise OutOfBytes {
  while !stop(self.byte()) {
    self.pos += 1
  }
}

///|
/// Whether `b` is ASCII whitespace.
fn is_space(b : Byte) -> Bool {
  b is (0x09 | 0x0A | 0x0C | 0x0D | 0x20)
}

///|
/// Whether `bytes` starts with `word`, which is in lower case, in any case.
fn starts_with_word(bytes : BytesView, word : Bytes) -> Bool {
  guard bytes.length() >= word.length() else { return false }
  for i, b in word {
    if ascii_lower(bytes[i]) != b {
      return false
    }
  }
  true
}

///|
fn ascii_lower(b : Byte) -> Byte {
  if b is (b'A'..<=b'Z') {
    b + 0x20
  } else {
    b
  }
}

///|
/// The loop of the prescan: the encoding of the first `<meta>` that
/// declares one. It only ends by finding one or by running out of bytes.
fn Scanner::meta_encoding(self : Scanner) -> Encoding raise OutOfBytes {
  for ;; {
    self.byte() |> ignore
    match self.bytes[self.pos:] {
      [b'<', b'!', b'-', b'-', ..] => {
        // The first `>` after `--`, which may be the `--` of `<!--`.
        self.pos += 4
        while !(self.byte() == b'>' &&
              self.bytes[self.pos - 2:self.pos] is [b'-', b'-']) {
          self.pos += 1
        }
      }
      [b'<', _, _, _, _, after, ..] if (is_space(after) || after == b'/') &&
        starts_with_word(self.bytes[self.pos + 1:], b"meta") => {
        self.pos += 5
        if self.meta() is Some(encoding) {
          return encoding
        }
      }
      [b'<', b'A'..<=b'Z' | b'a'..<=b'z', ..]
      | [b'<', b'/', b'A'..<=b'Z' | b'a'..<=b'z', ..] => {
        self.skip_until(b => is_space(b) || b == b'>')
        while self.attribute() is Some(_) {
          // "Repeatedly get an attribute until no further attributes can be
          // found"
        }
      }
      [b'<', b'!' | b'/' | b'?', ..] => self.skip_until(b => b == b'>')
      _ => ()
    }
    // "Next byte"
    self.pos += 1
  }
}

///|
/// The attributes of a `<meta>` element, from just after `<meta`: the
/// encoding they declare, if the prescan accepts it.
fn Scanner::meta(self : Scanner) -> Encoding? raise OutOfBytes {
  let names : Set[Bytes] = Set([])
  let mut got_pragma = false
  let mut need_pragma : Bool? = None
  // `None` while charset is null, `Some(None)` for a label of no encoding.
  let mut charset : Encoding?? = None
  // "Attributes"
  while self.attribute() is Some((name, value)) {
    if names.contains(name) {
      continue
    }
    names.add(name)
    match name {
      b"http-equiv" => if value == b"content-type" { got_pragma = true }
      b"content" =>
        if charset is None && content_encoding(value) is Some(encoding) {
          charset = Some(Some(encoding))
          need_pragma = Some(true)
        }
      b"charset" => {
        charset = Some(Encoding::from_label(isomorphic_decode(value)))
        need_pragma = Some(false)
      }
      _ => ()
    }
  }
  // "Processing"
  guard need_pragma is Some(need) else { return None }
  if need && !got_pragma {
    return None
  }
  match charset {
    Some(Some(Utf16Be | Utf16Le)) => Some(Utf8)
    Some(Some(XUserDefined)) => Some(Windows1252)
    Some(encoding) => encoding
    None => None
  }
}

///|
/// "Get an attribute": the name and value of the next attribute of a tag,
/// with ASCII letters in lower case, or `None` at the `>` that ends it.
fn Scanner::attribute(self : Scanner) -> (Bytes, Bytes)? raise OutOfBytes {
  self.skip_until(b => !is_space(b) && b != b'/')
  if self.byte() == b'>' {
    return None
  }
  let name = @buffer.Buffer()
  let value = @buffer.Buffer()
  for ;; {
    let b = self.byte()
    if b == b'=' && name.length() > 0 {
      self.pos += 1
      break
    } else if is_space(b) {
      // "Spaces"
      self.skip_until(b => !is_space(b))
      if self.byte() != b'=' {
        return Some((name.to_bytes(), value.to_bytes()))
      }
      self.pos += 1
      break
    } else if b is (b'/' | b'>') {
      return Some((name.to_bytes(), value.to_bytes()))
    }
    name.write_byte(ascii_lower(b))
    self.pos += 1
  }
  // "Value"
  self.skip_until(b => !is_space(b))
  let quote = self.byte()
  if quote is (b'"' | b'\'') {
    for ;; {
      self.pos += 1
      let b = self.byte()
      if b == quote {
        self.pos += 1
        return Some((name.to_bytes(), value.to_bytes()))
      }
      value.write_byte(ascii_lower(b))
    }
  }
  for ;; {
    let b = self.byte()
    if is_space(b) || b == b'>' {
      return Some((name.to_bytes(), value.to_bytes()))
    }
    value.write_byte(ascii_lower(b))
    self.pos += 1
  }
}

///|
/// "The algorithm for extracting a character encoding from a meta element",
/// applied to the value `s` of a `content` attribute.
fn content_encoding(s : BytesView) -> Encoding? {
  let mut position = 0
  for ;; {
    // "Loop": the next "charset", in any case.
    let mut start = position
    while !starts_with_word(s[start:], b"charset") {
      if start >= s.length() {
        return None
      }
      start += 1
    }
    let mut i = start + 7
    while i < s.length() && is_space(s[i]) {
      i += 1
    }
    if i >= s.length() || s[i] != b'=' {
      position = i
      continue
    }
    i += 1
    while i < s.length() && is_space(s[i]) {
      i += 1
    }
    if i >= s.length() {
      return None
    }
    let c = s[i]
    let mut end = i + 1
    if c is (b'"' | b'\'') {
      // The text up to the next quote of the same kind, if there is one.
      while end < s.length() && s[end] != c {
        end += 1
      }
      if end >= s.length() {
        return None
      }
      return Encoding::from_label(isomorphic_decode(s[i + 1:end]))
    }
    while end < s.length() && !(is_space(s[end]) || s[end] == b';') {
      end += 1
    }
    return Encoding::from_label(isomorphic_decode(s[i:end]))
  }
}

///|
/// "Get an XML encoding": the encoding an XML declaration at the start of
/// `bytes` names.
fn xml_encoding(bytes : BytesView) -> Encoding? {
  guard bytes is [b'<', b'?', b'x', b'm', b'l', ..] else { return None }
  guard bytes.find(b">") is Some(declaration_end) else { return None }
  guard bytes[:declaration_end].find(b"encoding") is Some(start) else {
    return None
  }
  // The `>` at `declaration_end` stops these loops.
  let mut pos = start + 8
  while bytes[pos] <= b' ' {
    pos += 1
  }
  if bytes[pos] != b'=' {
    return None
  }
  pos += 1
  while bytes[pos] <= b' ' {
    pos += 1
  }
  let quote = bytes[pos]
  if !(quote is (b'"' | b'\'')) {
    return None
  }
  pos += 1
  // The next quote of the same kind, which may come after the `>`.
  let mut end = pos
  while end < bytes.length() && bytes[end] != quote {
    end += 1
  }
  if end >= bytes.length() {
    return None
  }
  let label = bytes[pos:end]
  if label.iter().any(b => b <= b' ') {
    return None
  }
  match Encoding::from_label(isomorphic_decode(label)) {
    Some(Utf16Be | Utf16Le) => Some(Utf8)
    encoding => encoding
  }
}

///|
/// The string with a code point of the same value for each byte.
fn isomorphic_decode(bytes : BytesView) -> String {
  let s = StringBuilder()
  for b in bytes {
    s.write_char(b.to_int().unsafe_to_char())
  }
  s.to_string()
}
