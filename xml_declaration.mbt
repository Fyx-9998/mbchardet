// The XML declaration as XML 1.0, fifth edition
// (https://www.w3.org/TR/2008/REC-xml-20081126/), defines it; the numbers
// in the comments are those of its productions.

///|
/// The XML declaration at the very start of `bytes`, read as ASCII:
/// `Some(Some(name))` when it has an encoding declaration, with the
/// encoding name as written, `Some(None)` when it has none, and `None` when
/// `bytes` does not start with a declaration that matches the grammar,
/// up to its `?>`.
fn xml_declaration(bytes : BytesView) -> BytesView?? {
  // [23] XMLDecl ::= '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'
  let cursor = Cursor::{ bytes, pos: 0, }
  guard cursor.word(b"<?xml") else { return None }
  // [24] VersionInfo ::= S 'version' Eq ("'" VersionNum "'" | '"' VersionNum '"')
  guard cursor.space() &&
    cursor.word(b"version") &&
    cursor.eq() &&
    cursor.quoted() is Some(version) &&
    is_version_num(version) else {
    return None
  }
  let mut spaced = cursor.space()
  // [80] EncodingDecl ::= S 'encoding' Eq ('"' EncName '"' | "'" EncName "'" )
  let mut name = None
  if spaced && cursor.word(b"encoding") {
    guard cursor.eq() && cursor.quoted() is Some(value) && is_enc_name(value) else {
      return None
    }
    name = Some(value)
    spaced = cursor.space()
  }
  // [32] SDDecl ::= S 'standalone' Eq (("'" ('yes' | 'no') "'") | ('"' ('yes' | 'no') '"'))
  if spaced && cursor.word(b"standalone") {
    guard cursor.eq() && cursor.quoted() is Some(b"yes" | b"no") else {
      return None
    }
    cursor.space() |> ignore
  }
  guard cursor.word(b"?>") else { return None }
  Some(name)
}

///|
/// A position in the bytes of an XML declaration.
priv struct Cursor {
  bytes : BytesView
  mut pos : Int32
}

///|
/// Moves past `word` if the bytes continue with it.
fn Cursor::word(self : Cursor, word : Bytes) -> Bool {
  let rest = self.bytes[self.pos:]
  guard rest.length() >= word.length() && rest[:word.length()] == word else {
    return false
  }
  self.pos += word.length()
  true
}

///|
/// Moves past white space, `[3] S ::= (#x20 | #x9 | #xD | #xA)+`, and tells
/// whether there was any.
fn Cursor::space(self : Cursor) -> Bool {
  let start = self.pos
  while self.pos < self.bytes.length() &&
        self.bytes[self.pos] is (b' ' | b'\t' | b'\r' | b'\n') {
    self.pos += 1
  }
  self.pos > start
}

///|
/// Moves past `[25] Eq ::= S? '=' S?`.
fn Cursor::eq(self : Cursor) -> Bool {
  self.space() |> ignore
  guard self.word(b"=") else { return false }
  self.space() |> ignore
  true
}

///|
/// Moves past a value in single or double quotes and returns what is
/// between them.
fn Cursor::quoted(self : Cursor) -> BytesView? {
  guard self.pos < self.bytes.length() &&
    self.bytes[self.pos] is (b'"' | b'\'' as quote) else {
    return None
  }
  let start = self.pos + 1
  let mut end = start
  while end < self.bytes.length() && self.bytes[end] != quote {
    end += 1
  }
  guard end < self.bytes.length() else { return None }
  self.pos = end + 1
  Some(self.bytes[start:end])
}

///|
/// `[26] VersionNum ::= '1.' [0-9]+`
fn is_version_num(value : BytesView) -> Bool {
  value is [b'1', b'.', .. digits] &&
  digits.length() > 0 &&
  digits.iter().all(b => b is (b'0'..<=b'9'))
}

///|
/// `[81] EncName ::= [A-Za-z] ([A-Za-z0-9._] | '-')*`
fn is_enc_name(value : BytesView) -> Bool {
  value is [b'A'..<=b'Z' | b'a'..<=b'z', .. rest] &&
  rest
  .iter()
  .all(b => {
    b is (b'A'..<=b'Z' | b'a'..<=b'z' | b'0'..<=b'9' | b'.' | b'_' | b'-')
  })
}
