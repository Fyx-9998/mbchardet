// The detector of chardetng 1.0.0 (EncodingDetector in src/lib.rs,
// Apache-2.0 OR MIT, Copyright Mozilla Foundation), ported without its CJK
// candidates so far. See NOTICE.

///|
priv enum Inner {
  Utf8Check(Utf8Validator)
  Latin(LatinCandidate)
  NonLatinCased(NonLatinCasedCandidate)
  Caseless(CaselessCandidate)
  ArabicFrench(ArabicFrenchCandidate)
  Logical(LogicalCandidate)
  Visual(VisualCandidate)
}

///|
fn Inner::feed_single_byte(self : Inner, buffer : BytesView) -> Int64? {
  match self {
    Latin(c) => c.feed(buffer)
    NonLatinCased(c) => c.feed(buffer)
    Caseless(c) => c.feed(buffer)
    ArabicFrench(c) => c.feed(buffer)
    Logical(c) => c.feed(buffer)
    Visual(c) => c.feed(buffer)
    Utf8Check(_) => panic()
  }
}

///|
/// The score change from `buffer`, or `None` if `buffer` rules the encoding
/// out.
fn Inner::feed(self : Inner, buffer : BytesView, last : Bool) -> Int64? {
  if self is Utf8Check(validator) {
    if !validator.feed(buffer) {
      return None
    }
    if last && validator.finish() is Invalid(_) {
      return None
    }
    return Some(0)
  }
  guard self.feed_single_byte(buffer) is Some(score) else { return None }
  if !last {
    return Some(score)
  }
  // Treat EOF as space-like
  match self.feed_single_byte(b" "[:]) {
    Some(additional) => Some(score + additional)
    None => None
  }
}

///|
priv struct Candidate {
  inner : Inner
  encoding : Encoding
  mut score : Int64?
}

///|
fn Candidate::new(inner : Inner, encoding : Encoding) -> Candidate {
  { inner, encoding, score: Some(0), }
}

///|
fn Candidate::single_byte(index : Int32) -> Candidate {
  let data = single_byte_data[index]
  let inner : Inner = match index {
    WINDOWS_1252_INDEX
    | WINDOWS_1250_INDEX
    | ISO_8859_2_INDEX
    | WINDOWS_1252_ICELANDIC_INDEX
    | WINDOWS_1254_INDEX
    | WINDOWS_1257_INDEX
    | ISO_8859_13_INDEX
    | WINDOWS_1258_INDEX
    | ISO_8859_4_INDEX => Latin(LatinCandidate::new(data))
    WINDOWS_1251_INDEX
    | WINDOWS_1253_INDEX
    | ISO_8859_7_INDEX
    | KOI8_U_INDEX
    | IBM866_INDEX
    | ISO_8859_5_INDEX => NonLatinCased(NonLatinCasedCandidate::new(data))
    WINDOWS_874_INDEX | ISO_8859_6_INDEX =>
      Caseless(CaselessCandidate::new(data))
    WINDOWS_1256_INDEX => ArabicFrench(ArabicFrenchCandidate::new(data))
    WINDOWS_1255_INDEX => Logical(LogicalCandidate::new(data))
    ISO_8859_8_INDEX => Visual(VisualCandidate::new(data))
    _ => panic()
  }
  Candidate::new(inner, data.encoding)
}

///|
fn Candidate::feed(self : Candidate, buffer : BytesView, last : Bool) -> Unit {
  if self.score is Some(old) {
    self.score = match self.inner.feed(buffer, last) {
      Some(delta) => Some(old + delta)
      None => None
    }
  }
}

///|
/// The score without a top-level domain hint, as `find_score` in chardetng
/// computes it.
fn Candidate::generic_score(self : Candidate) -> Int64? {
  let longest_word = match self.inner {
    NonLatinCased(c) => c.longest_word
    Caseless(c) => c.longest_word
    ArabicFrench(c) => c.longest_word
    Logical(c) => c.longest_word
    Visual(c) => c.longest_word
    Utf8Check(_) | Latin(_) => 2
  }
  if longest_word < 2 {
    None
  } else {
    self.score
  }
}

///|
/// Detects the encoding of a byte stream that arrives in chunks, by scoring
/// how plausible the bytes are in each encoding.
///
/// This is a port of the detector of chardetng 1.0.0
/// (<https://github.com/hsivonen/chardetng>), the detector Firefox uses for
/// unlabeled legacy content. So far it contains chardetng's candidates for
/// UTF-8 and the single-byte encodings; the CJK candidates, and with them a
/// final guess, are not ported yet.
struct Detector {
  candidates : Array[Candidate]
  mut non_ascii_seen : Int64
  // Up to two bytes of context before the first non-ASCII byte, which
  // chardetng needs for Spanish "n.º".
  mut before_non_ascii : Bytes
  mut esc_seen : Bool
  mut closed : Bool
}

///|
/// A detector that has seen no input yet.
pub fn Detector::new() -> Detector {
  // chardetng's candidate order, without the CJK candidates. When two
  // candidates report the same encoding, `score` uses the first.
  let candidates = [Candidate::new(Utf8Check(Utf8Validator::new()), Utf8)]
  for
    index in [
      ISO_8859_8_INDEX,
      WINDOWS_1252_INDEX,
      WINDOWS_1251_INDEX,
      WINDOWS_1250_INDEX,
      ISO_8859_2_INDEX,
      WINDOWS_1256_INDEX,
      WINDOWS_1252_ICELANDIC_INDEX,
      WINDOWS_1254_INDEX,
      WINDOWS_874_INDEX,
      WINDOWS_1255_INDEX,
      WINDOWS_1253_INDEX,
      ISO_8859_7_INDEX,
      WINDOWS_1257_INDEX,
      ISO_8859_13_INDEX,
      KOI8_U_INDEX,
      IBM866_INDEX,
      ISO_8859_6_INDEX,
      WINDOWS_1258_INDEX,
      ISO_8859_4_INDEX,
      ISO_8859_5_INDEX,
    ] {
    candidates.push(Candidate::single_byte(index))
  }
  {
    candidates,
    non_ascii_seen: 0,
    before_non_ascii: b"",
    esc_seen: false,
    closed: false,
  }
}

///|
fn Detector::feed_candidates(
  self : Detector,
  buffer : BytesView,
  last : Bool,
) -> Unit {
  for candidate in self.candidates {
    candidate.feed(buffer, last)
  }
  for byte in buffer {
    if byte >= b'\x80' {
      self.non_ascii_seen += 1
    }
  }
}

///|
/// Keeps the last two bytes of the ASCII input seen so far.
fn Detector::remember_before_non_ascii(
  self : Detector,
  buffer : BytesView,
) -> Unit {
  let len = buffer.length()
  if len >= 2 {
    self.before_non_ascii = buffer[len - 2:].to_owned()
  } else if len == 1 {
    let kept = self.before_non_ascii
    self.before_non_ascii = if kept.length() == 0 {
      buffer.to_owned()
    } else {
      Bytes::from_array([kept[kept.length() - 1], buffer[0]])
    }
  }
}

///|
/// Feeds the next chunk of the stream. Set `last` on the final chunk, which
/// may be empty; the end of the stream then counts as a space after the last
/// word. How the stream is split into chunks is up to the caller.
///
/// Returns `true` once the stream has contained a non-ASCII byte.
///
/// Leading ASCII is skipped, apart from the two bytes before the first
/// non-ASCII byte or ESC: as in chardetng, pairs of ASCII bytes do not
/// contribute to any score.
///
/// Panics if called again after a call with `last` set to `true`.
pub fn Detector::feed(
  self : Detector,
  chunk : BytesView,
  last~ : Bool = false,
) -> Bool {
  if self.closed {
    abort("Detector::feed: called after the last chunk was fed")
  }
  if last {
    self.closed = true
  }
  let mut start = 0
  if self.non_ascii_seen == 0 && !self.esc_seen {
    let mut up_to = chunk.length()
    for i, byte in chunk {
      if byte >= b'\x80' {
        up_to = i
        break
      }
    }
    start = up_to
    for i in 0..<up_to {
      if chunk[i] == b'\x1B' {
        self.esc_seen = true
        start = i
        break
      }
    }
    if start == chunk.length() {
      self.remember_before_non_ascii(chunk)
      return self.non_ascii_seen != 0
    }
    if start == 0 || start == 1 {
      let before = self.before_non_ascii
      self.before_non_ascii = b""
      self.feed_candidates(before[:], false)
      start = 0
    } else {
      start = start - 2
    }
  }
  self.feed_candidates(chunk[start:], last)
  self.non_ascii_seen != 0
}

///|
/// The score of `encoding` for the stream fed so far, ignoring any
/// top-level domain hint: higher means more plausible. Scores only compare
/// encodings for the same input.
///
/// Returns `None` when the input has ruled `encoding` out: a byte that
/// encoding does not use, invalid UTF-8, or, for encodings of non-Latin
/// scripts, no word of at least two letters. Also `None` for UTF-16, which
/// is only recognized by its byte order mark (see `sniff_bom`).
///
/// The scores are those chardetng's `find_score` computes for the same
/// input fed in the same chunks.
pub fn Detector::score(self : Detector, encoding : Encoding) -> Int64? {
  for candidate in self.candidates {
    if candidate.encoding == encoding {
      return candidate.generic_score()
    }
  }
  None
}
