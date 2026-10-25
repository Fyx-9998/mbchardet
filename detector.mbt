// The detector of chardetng 1.0.0 (EncodingDetector in src/lib.rs,
// Apache-2.0 OR MIT, Copyright Mozilla Foundation). See NOTICE.

///|
priv enum Inner {
  Utf8Check(Utf8Validator)
  Latin(LatinCandidate)
  NonLatinCased(NonLatinCasedCandidate)
  Caseless(CaselessCandidate)
  ArabicFrench(ArabicFrenchCandidate)
  Logical(LogicalCandidate)
  Visual(VisualCandidate)
  Gbk(GbkCandidate)
  Big5(Big5Candidate)
  ShiftJis(ShiftJisCandidate)
  EucJp(EucJpCandidate)
  Iso2022Jp(Iso2022JpCandidate)
  EucKr(EucKrCandidate)
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
    Utf8Check(_)
    | Gbk(_)
    | Big5(_)
    | ShiftJis(_)
    | EucJp(_)
    | Iso2022Jp(_)
    | EucKr(_) => panic()
  }
}

///|
/// The score change from `buffer`, or `None` if `buffer` rules the encoding
/// out.
fn Inner::feed(self : Inner, buffer : BytesView, last : Bool) -> Int64? {
  match self {
    Utf8Check(validator) => {
      if !validator.feed(buffer) {
        return None
      }
      if last && validator.finish() is Invalid(_) {
        return None
      }
      return Some(0)
    }
    Gbk(c) => return c.feed(buffer, last)
    Big5(c) => return c.feed(buffer, last)
    ShiftJis(c) => return c.feed(buffer, last)
    EucJp(c) => return c.feed(buffer, last)
    Iso2022Jp(c) => return c.feed(buffer, last)
    EucKr(c) => return c.feed(buffer, last)
    _ => ()
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
/// The score of the candidate at position `encoding` under `tld`, as
/// `Candidate::score` in chardetng computes it. `expectation_is_valid` tells
/// whether an encoding native to `tld` is still possible.
fn Candidate::score_for(
  self : Candidate,
  encoding : Int32,
  tld : Tld,
  expectation_is_valid : Bool,
) -> Int64? {
  // Encodings of non-Latin scripts need a word of at least two letters;
  // all but the cased ones are exempt when the TLD expects them.
  let longest_word = match self.inner {
    NonLatinCased(c) => Some((c.longest_word, false))
    Caseless(c) => Some((c.longest_word, true))
    ArabicFrench(c) => Some((c.longest_word, true))
    Logical(c) => Some((c.longest_word, true))
    Visual(c) => Some((c.longest_word, true))
    _ => None
  }
  if longest_word is Some((length, native_exempt)) &&
    length < 2 &&
    !(native_exempt && encoding_is_native_to_tld(tld, encoding)) {
    return None
  }
  if tld == Generic {
    return self.score
  }
  guard self.score is Some(score) else { return None }
  if encoding == encoding_for_tld(tld) {
    return Some(score + 1)
  }
  if encoding_is_native_to_tld(tld, encoding) {
    return Some(score)
  }
  if expectation_is_valid {
    return Some(score - score_adjustment(score, encoding, tld))
  }
  // If the expectation is no longer valid, fall back to generic behavior.
  Some(score)
}

///|
/// The punctuation count of a Hebrew candidate.
fn Candidate::plausible_punctuation(self : Candidate) -> Int64 {
  match self.inner {
    Logical(c) => c.plausible_punctuation
    Visual(c) => c.plausible_punctuation
    _ => panic()
  }
}

///|
/// Detects the encoding of a byte stream that arrives in chunks, by scoring
/// how plausible the bytes are in each encoding.
///
/// This is a port of the detector of chardetng 1.0.0
/// (<https://github.com/hsivonen/chardetng>), the detector Firefox uses for
/// unlabeled legacy content: its candidates for UTF-8, GBK, Big5, Shift_JIS,
/// EUC-JP, ISO-2022-JP, EUC-KR and the single-byte encodings, the scores they
/// give, and the guess that chooses between them.
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
///
/// With `allow_iso_2022_jp` set to `false`, ISO-2022-JP is ruled out from
/// the start. chardetng leaves this choice to its caller because a browser
/// that decodes a page able to run scripts should not accept ISO-2022-JP,
/// which can hide markup in escape sequences; email and plain files can.
pub fn Detector::new(allow_iso_2022_jp~ : Bool = true) -> Detector {
  // chardetng's candidate order; the CANDIDATE_* constants in tld.mbt name
  // the positions. When two candidates report the same encoding, `score`
  // uses the first.
  let iso_2022_jp = Candidate::new(
    Iso2022Jp(Iso2022JpCandidate::new()),
    Iso2022Jp,
  )
  if !allow_iso_2022_jp {
    iso_2022_jp.score = None
  }
  let candidates = [
    Candidate::new(Utf8Check(Utf8Validator::new()), Utf8),
    iso_2022_jp,
    Candidate::single_byte(ISO_8859_8_INDEX),
    Candidate::new(Gbk(GbkCandidate::new()), Gbk),
    Candidate::new(EucJp(EucJpCandidate::new()), EucJp),
    Candidate::new(EucKr(EucKrCandidate::new()), EucKr),
    Candidate::new(ShiftJis(ShiftJisCandidate::new()), ShiftJis),
    Candidate::new(Big5(Big5Candidate::new()), Big5),
  ]
  for
    index in [
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
/// scripts, no word of at least two letters. Also `None` for the encodings
/// a detector does not score (see `Detector::encodings`), such as UTF-16,
/// which is only recognized by its byte order mark (see `sniff_bom`).
///
/// The scores are those chardetng's `find_score` computes for the same
/// input fed in the same chunks.
pub fn Detector::score(self : Detector, encoding : Encoding) -> Int64? {
  for i, candidate in self.candidates {
    if candidate.encoding == encoding {
      return candidate.score_for(i, Generic, false)
    }
  }
  None
}

///|
/// The encodings the stream fed so far has not ruled out, with their scores
/// as `score` gives them, highest first. Equal scores keep the order of
/// `Detector::encodings()`. The encodings left out are those ruled out.
///
/// The guess is not always the first of them: `guess` also weighs the
/// top-level domain and applies the rules it lists.
pub fn Detector::scores(self : Detector) -> Array[(Encoding, Int64)] {
  let scored = []
  for i, encoding in Detector::encodings() {
    if self.score(encoding) is Some(score) {
      scored.push((i, encoding, score))
    }
  }
  scored.sort_by((a, b) => {
    let by_score = b.2.compare(a.2)
    if by_score != 0 {
      by_score
    } else {
      a.0.compare(b.0)
    }
  })
  scored.map(entry => (entry.1, entry.2))
}

///|
/// The 26 encodings a detector scores, in the order of `Encoding::all()`:
/// UTF-8 and the legacy encodings chardetng can guess.
pub fn Detector::encodings() -> Array[Encoding] {
  let scored = Detector::new().candidates.map(candidate => candidate.encoding)
  Encoding::all().filter(encoding => scored.contains(encoding))
}

///|
/// Panics unless `tld` looks like the label chardetng expects.
fn check_tld(caller : String, tld : String) -> Unit {
  if contains_upper_case_period_or_non_ascii(tld) {
    abort(
      "\{caller}: expected the last label of a host name in lower case, in Punycode if internationalized (such as \"jp\" or \"xn--p1ai\"), got \"\{tld}\"",
    )
  }
}

///|
/// The encoding the stream fed so far is most likely in, as chardetng's
/// `guess` decides it:
///
/// - Input that is ASCII apart from ISO-2022-JP escape sequences is
///   ISO-2022-JP, unless the detector was created without it.
/// - Valid UTF-8 is UTF-8 if `allow_utf8` is `true`, else the default
///   encoding of `tld`. chardetng's documentation asks browsers to deny
///   UTF-8 for HTML not loaded from a file, unless the user asked for
///   detection, so that pages do not come to depend on it.
/// - Otherwise the candidate with the highest score wins, the default of
///   `tld` if none scores above zero.
///
/// `tld` is the last label of the host name the input came from, in lower
/// case and in Punycode if internationalized, such as `"jp"`. It favors the
/// encodings expected for that domain. Without it, the guess is the one for
/// a generic domain such as `"com"`. Use `tld_may_affect_guess` to know
/// whether a label has any effect.
///
/// The guess never is UTF-16, which only a byte order mark identifies; check
/// `sniff_bom` first. It does not end the stream: feeding more input and
/// guessing again is fine.
///
/// Panics if `tld` contains an upper-case letter, a period or a character
/// outside ASCII, which are signs of a label not extracted correctly.
pub fn Detector::guess(
  self : Detector,
  tld? : String,
  allow_utf8~ : Bool = true,
) -> Encoding {
  let mut tld_type = match tld {
    Some(label) => {
      check_tld("Detector::guess", label)
      classify_tld(label)
    }
    None => Generic
  }
  let candidates = self.candidates
  if self.non_ascii_seen == 0 &&
    self.esc_seen &&
    candidates[CANDIDATE_ISO_2022_JP].score is Some(_) {
    return Iso2022Jp
  }
  if candidates[CANDIDATE_UTF_8].score is Some(_) {
    if allow_utf8 {
      return Utf8
    }
    return candidates[encoding_for_tld(tld_type)].encoding
  }
  let mut encoding = candidates[encoding_for_tld(tld_type)].encoding
  let mut max = 0L
  let mut expectation_is_valid = false
  if tld_type != Generic {
    for i in FIRST_NORMAL..<candidates.length() {
      if encoding_is_native_to_tld(tld_type, i) &&
        candidates[i].score is Some(_) {
        expectation_is_valid = true
        break
      }
    }
  }
  if !expectation_is_valid {
    // Flip Chinese and Central around
    match tld_type {
      Simplified =>
        if candidates[CANDIDATE_BIG5].score is Some(_) {
          tld_type = Traditional
          expectation_is_valid = true
        }
      Traditional =>
        if candidates[CANDIDATE_GBK].score is Some(_) {
          tld_type = Simplified
          expectation_is_valid = true
        }
      CentralWindows =>
        if candidates[CANDIDATE_CENTRAL_ISO].score is Some(_) {
          tld_type = CentralIso
          expectation_is_valid = true
        }
      CentralIso =>
        if candidates[CANDIDATE_CENTRAL_WINDOWS].score is Some(_) {
          tld_type = CentralWindows
          expectation_is_valid = true
        }
      _ => ()
    }
  }
  for i in FIRST_NORMAL..<candidates.length() {
    if candidates[i].score_for(i, tld_type, expectation_is_valid) is Some(score) &&
      score > max {
      max = score
      encoding = candidates[i].encoding
    }
  }
  // Visual Hebrew wins over logical Hebrew when its punctuation is more
  // plausible.
  let visual = candidates[CANDIDATE_VISUAL]
  if visual.score_for(CANDIDATE_VISUAL, tld_type, expectation_is_valid)
    is Some(visual_score) &&
    (visual_score > max || encoding == Windows1255) &&
    visual.plausible_punctuation() >
    candidates[CANDIDATE_LOGICAL].plausible_punctuation() {
    encoding = Iso8859_8
  }
  encoding
}

///|
/// Whether `tld` can change what `Detector::guess` returns, that is, whether
/// chardetng treats it as other than generic. An application can use it to
/// skip offering a guess without the domain when that would not differ.
///
/// Panics under the same conditions as `Detector::guess`.
pub fn tld_may_affect_guess(tld : String) -> Bool {
  check_tld("tld_may_affect_guess", tld)
  classify_tld(tld) != Generic
}
