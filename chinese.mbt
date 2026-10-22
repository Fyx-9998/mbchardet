// The GBK and Big5 candidates of chardetng 1.0.0, ported from src/lib.rs
// (Apache-2.0 OR MIT, Copyright Mozilla Foundation). See NOTICE.

///|
/// Manually calibrated relative to windows-1256 Arabic.
const CJK_BASE_SCORE : Int64 = 41

///|
const CJK_SECONDARY_BASE_SCORE : Int64 = 20

///|
const BIG5_SCORE_PER_LEVEL_1_HANZI : Int64 = CJK_BASE_SCORE

///|
const BIG5_SCORE_PER_OTHER_HANZI : Int64 = CJK_SECONDARY_BASE_SCORE

///|
/// More severe than other PUA penalties to avoid misdetecting EUC-KR.
const BIG5_PUA_PENALTY : Int64 = -(CJK_BASE_SCORE * 30)

///|
const BIG5_SINGLE_BYTE_EXTENSION_PENALTY : Int64 = -(CJK_BASE_SCORE * 40)

///|
const GBK_SCORE_PER_LEVEL_1 : Int64 = CJK_BASE_SCORE

///|
const GBK_SCORE_PER_LEVEL_2 : Int64 = CJK_SECONDARY_BASE_SCORE

///|
const GBK_SCORE_PER_NON_EUC : Int64 = CJK_SECONDARY_BASE_SCORE / 4

///|
const GBK_PUA_PENALTY : Int64 = -(CJK_BASE_SCORE * 10)

///|
const GBK_SINGLE_BYTE_EXTENSION_PENALTY : Int64 = GBK_PUA_PENALTY * 4

///|
/// Smaller than LATIN_ADJACENCY_PENALTY.
const CJK_LATIN_ADJACENCY_PENALTY : Int64 = -CJK_BASE_SCORE

///|
const CJ_PUNCTUATION : Int64 = CJK_BASE_SCORE / 2

///|
const CJK_OTHER : Int64 = CJK_SECONDARY_BASE_SCORE / 4

///|
priv enum LatinCj {
  AsciiLetter
  Cj
  Other
} derive(Eq)

///|
/// A bonus for the 128 most frequent characters in `table`, larger for the
/// more frequent.
fn cjk_extra_score(u : Int32, table : FixedArray[Int32]) -> Int64 {
  for i, frequent in table {
    if frequent == u {
      return ((128 - i) / 16).to_int64()
    }
  }
  0
}

///|
// Shift_JIS and Big5
fn problematic_lead(b : Int32) -> Bool {
  b is (0x91..<=0x97 | 0x9A | 0x8A | 0x9B | 0x8B | 0x9E | 0x8E | 0xB0)
}

///|
// GBK and EUC-KR
fn more_problematic_lead(b : Int32) -> Bool {
  problematic_lead(b) || b == 0x82 || b == 0x84 || b == 0x85 || b == 0xA0
}

///|
fn is_ascii_letter(u : Int32) -> Bool {
  (u >= 'a'.to_int() && u <= 'z'.to_int()) ||
  (u >= 'A'.to_int() && u <= 'Z'.to_int())
}

///|
/// Ideographic punctuation that sets Chinese apart from Korean and Japanese.
fn is_cj_punctuation(u : Int32) -> Bool {
  u
  is (0x3000
  | 0x3001
  | 0x3002
  | 0xFF08
  | 0xFF09
  | 0xFF01
  | 0xFF0C
  | 0xFF1B
  | 0xFF1F)
}

///|
priv struct GbkCandidate {
  decoder : GbkDecoder
  mut prev_byte : Int32
  mut prev : LatinCj
  mut pending_score : Int64?
}

///|
fn GbkCandidate::new() -> GbkCandidate {
  {
    decoder: GbkDecoder::new(),
    prev_byte: 0,
    prev: Other,
    pending_score: None,
  }
}

///|
fn GbkCandidate::maybe_set_as_pending(self : GbkCandidate, s : Int64) -> Int64 {
  if self.prev == Cj || !more_problematic_lead(self.prev_byte) {
    s
  } else {
    self.pending_score = Some(s)
    0
  }
}

///|
/// Adds the pending score, if any, to the score of this byte.
fn GbkCandidate::take_pending(self : GbkCandidate) -> Int64 {
  match self.pending_score {
    Some(pending) => {
      self.pending_score = None
      pending
    }
    None => 0
  }
}

///|
/// The score of one decoded BMP character `u`, `b` being its last byte.
fn GbkCandidate::score_bmp(self : GbkCandidate, u : Int32, b : Int32) -> Int64 {
  let mut score = 0L
  if is_ascii_letter(u) {
    // Discard pending score
    self.pending_score = None
    if self.prev == Cj {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = AsciiLetter
  } else if u == 0x20AC {
    // Euro sign. Discard pending score.
    self.pending_score = None
    self.prev = Other
  } else if u >= 0x4E00 && u <= 0x9FA5 {
    score += self.take_pending()
    if b >= 0xA1 && b <= 0xFE {
      match self.prev_byte {
        0xA1..<=0xD7 => {
          score += GBK_SCORE_PER_LEVEL_1
          score += cjk_extra_score(u, frequent_simplified)
        }
        0xD8..<=0xFE => score += GBK_SCORE_PER_LEVEL_2
        _ => score += GBK_SCORE_PER_NON_EUC
      }
    } else {
      score += self.maybe_set_as_pending(GBK_SCORE_PER_NON_EUC)
    }
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else if (u >= 0x3400 && u < 0xA000) || (u >= 0xF900 && u < 0xFB00) {
    score += self.take_pending()
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else if u >= 0xE000 && u < 0xF900 {
    score += self.take_pending()
    // Treat the GB18030-required PUA mappings as non-EUC ideographs.
    if u
      is (0xE78D..<=0xE796
      | 0xE816..<=0xE818
      | 0xE81E
      | 0xE826
      | 0xE82B
      | 0xE82C
      | 0xE831
      | 0xE832
      | 0xE83B
      | 0xE843
      | 0xE854
      | 0xE855
      | 0xE864) {
      score += GBK_SCORE_PER_NON_EUC
      if self.prev == AsciiLetter {
        score += CJK_LATIN_ADJACENCY_PENALTY
      }
      self.prev = Cj
    } else {
      score += GBK_PUA_PENALTY
      self.prev = Other
    }
  } else {
    if is_cj_punctuation(u) {
      score += self.take_pending()
      score += CJ_PUNCTUATION
    } else if u <= 0x7F {
      // Discard pending score
      self.pending_score = None
    } else {
      score += self.take_pending()
      score += CJK_OTHER
    }
    self.prev = Other
  }
  score
}

///|
/// The score of a character outside the BMP, `high` being its high
/// surrogate.
fn GbkCandidate::score_astral(self : GbkCandidate, high : Int32) -> Int64 {
  let mut score = self.take_pending()
  if high >= 0xDB80 && high <= 0xDBFF {
    score += GBK_PUA_PENALTY
    self.prev = Other
  } else if high >= 0xD480 && high < 0xD880 {
    score += GBK_SCORE_PER_NON_EUC
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else {
    score += CJK_OTHER
    self.prev = Other
  }
  score
}

///|
fn GbkCandidate::feed(
  self : GbkCandidate,
  buffer : BytesView,
  last : Bool,
) -> Int64? {
  let mut score = 0L
  for byte in buffer {
    let b = byte.to_int()
    match self.decoder.feed(b) {
      Pending => ()
      Unit(u) => score += self.score_bmp(u, b)
      Units(high, _) => score += self.score_astral(high)
      // After the two single-byte extensions below chardetng starts a new
      // decoder; GbkDecoder already starts over after a malformed sequence.
      Malformed(malformed_len) =>
        if (
            self.prev_byte == 0xA0 ||
            self.prev_byte == 0xFE ||
            self.prev_byte == 0xFD
          ) &&
          (b < 0x80 || b == 0xFF) {
          // Mac OS Chinese Simplified single-byte that conflicts with code
          // page GBK lead byte followed by ASCII or a non-conflicting
          // single-byte extension.
          self.pending_score = None
          score += GBK_SINGLE_BYTE_EXTENSION_PENALTY
          if is_ascii_letter(b) {
            self.prev = AsciiLetter
          } else if b == 0xFF {
            score += GBK_SINGLE_BYTE_EXTENSION_PENALTY
            self.prev = Other
          } else {
            self.prev = Other
          }
        } else if malformed_len == 1 && b == 0xFF {
          // Mac OS Chinese Simplified single-byte extension that doesn't
          // conflict with lead bytes
          self.pending_score = None
          score += GBK_SINGLE_BYTE_EXTENSION_PENALTY
          self.prev = Other
        } else {
          return None
        }
    }
    self.prev_byte = b
  }
  if last && self.decoder.incomplete() {
    return None
  }
  Some(score)
}

///|
priv struct Big5Candidate {
  decoder : Big5Decoder
  mut prev : LatinCj
  mut prev_byte : Int32
  mut pending_score : Int64?
}

///|
fn Big5Candidate::new() -> Big5Candidate {
  {
    decoder: Big5Decoder::new(),
    prev: Other,
    prev_byte: 0,
    pending_score: None,
  }
}

///|
fn Big5Candidate::maybe_set_as_pending(
  self : Big5Candidate,
  s : Int64,
) -> Int64 {
  if self.prev == Cj || !problematic_lead(self.prev_byte) {
    s
  } else {
    self.pending_score = Some(s)
    0
  }
}

///|
fn Big5Candidate::take_pending(self : Big5Candidate) -> Int64 {
  match self.pending_score {
    Some(pending) => {
      self.pending_score = None
      pending
    }
    None => 0
  }
}

///|
fn Big5Candidate::score_bmp(self : Big5Candidate, u : Int32) -> Int64 {
  let mut score = 0L
  if is_ascii_letter(u) {
    // Discard pending score
    self.pending_score = None
    if self.prev == Cj {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = AsciiLetter
  } else if (u >= 0x3400 && u < 0xA000) || (u >= 0xF900 && u < 0xFB00) {
    score += self.take_pending()
    if self.prev_byte >= 0xA4 && self.prev_byte <= 0xC6 {
      score += self.maybe_set_as_pending(BIG5_SCORE_PER_LEVEL_1_HANZI)
    } else {
      score += self.maybe_set_as_pending(BIG5_SCORE_PER_OTHER_HANZI)
    }
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else {
    if is_cj_punctuation(u) {
      score += self.take_pending()
      // Not really needed for CJK distinction but let's give non-zero
      // score for these common byte pairs anyway.
      score += CJ_PUNCTUATION
    } else if u <= 0x7F {
      // Discard pending score
      self.pending_score = None
    } else {
      score += self.take_pending()
      score += CJK_OTHER
    }
    self.prev = Other
  }
  score
}

///|
/// The score of two code units: a base letter with a combining mark, or a
/// surrogate pair.
fn Big5Candidate::score_pair(self : Big5Candidate, first : Int32) -> Int64 {
  let mut score = self.take_pending()
  if first == 0xCA || first == 0xEA {
    score += CJK_OTHER
    self.prev = Other
  } else {
    score += self.maybe_set_as_pending(BIG5_SCORE_PER_OTHER_HANZI)
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  }
  score
}

///|
fn Big5Candidate::feed(
  self : Big5Candidate,
  buffer : BytesView,
  last : Bool,
) -> Int64? {
  let mut score = 0L
  for byte in buffer {
    let b = byte.to_int()
    match self.decoder.feed(b) {
      Pending => ()
      Unit(u) => score += self.score_bmp(u)
      Units(first, _) => score += self.score_pair(first)
      Malformed(malformed_len) =>
        if self.prev_byte >= 0x81 &&
          self.prev_byte <= 0xFE &&
          ((b >= 0x40 && b <= 0x7E) || (b >= 0xA1 && b <= 0xFE)) {
          // The byte pair is in the Big5 range but unmapped. Treat as PUA to
          // avoid rejecting Big5-UAO, etc. We don't reprocess `b` even if
          // ASCII, since it's logically part of the pair.
          score += self.take_pending()
          score += BIG5_PUA_PENALTY
          // Assume Hanzi semantics
          if self.prev == AsciiLetter {
            score += CJK_LATIN_ADJACENCY_PENALTY
          }
          self.prev = Cj
        } else if (
            self.prev_byte == 0xA0 ||
            self.prev_byte == 0xFD ||
            self.prev_byte == 0xFE
          ) &&
          (b < 0x80 || b == 0xFF) {
          // Mac OS Chinese Traditional single-byte that conflicts with code
          // page Big5 lead byte followed by ASCII or a non-conflicting
          // single-byte extension.
          self.pending_score = None
          score += BIG5_SINGLE_BYTE_EXTENSION_PENALTY
          if is_ascii_letter(b) {
            self.prev = AsciiLetter
          } else if b == 0xFF {
            score += BIG5_SINGLE_BYTE_EXTENSION_PENALTY
            self.prev = Other
          } else {
            self.prev = Other
          }
        } else if malformed_len == 1 && b == 0xFF {
          // Mac OS Chinese Traditional single-byte extension that doesn't
          // conflict with lead bytes
          self.pending_score = None
          score += BIG5_SINGLE_BYTE_EXTENSION_PENALTY
          self.prev = Other
        } else {
          return None
        }
    }
    self.prev_byte = b
  }
  if last && self.decoder.incomplete() {
    return None
  }
  Some(score)
}
