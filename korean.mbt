// The EUC-KR candidate of chardetng 1.0.0, ported from src/lib.rs
// (Apache-2.0 OR MIT, Copyright Mozilla Foundation). See NOTICE. The
// constants shared with the other CJK candidates are in chinese.mbt.

///|
const EUC_KR_SCORE_PER_EUC_HANGUL : Int64 = CJK_BASE_SCORE + 1

///|
const EUC_KR_SCORE_PER_NON_EUC_HANGUL : Int64 = CJK_SECONDARY_BASE_SCORE / 5

///|
const EUC_KR_SCORE_PER_HANJA : Int64 = CJK_SECONDARY_BASE_SCORE / 2

///|
const EUC_KR_HANJA_AFTER_HANGUL_PENALTY : Int64 = -(CJK_BASE_SCORE * 10)

///|
const EUC_KR_LONG_WORD_PENALTY : Int64 = -6

///|
/// Breaks the tie in favor of GBK.
const EUC_KR_PUA_PENALTY : Int64 = GBK_PUA_PENALTY - 1

///|
const EUC_KR_MAC_KOREAN_PENALTY : Int64 = EUC_KR_PUA_PENALTY * 2

///|
const EUC_KR_SINGLE_BYTE_EXTENSION_PENALTY : Int64 = EUC_KR_MAC_KOREAN_PENALTY

///|
priv enum LatinKorean {
  AsciiLetter
  Hangul
  Hanja
  Other
} derive(Eq)

///|
priv struct EucKrCandidate {
  decoder : EucKrDecoder
  mut prev_byte : Int32
  mut prev_was_euc_range : Bool
  mut prev : LatinKorean
  mut current_word_len : Int64
  mut pending_score : Int64?
}

///|
fn EucKrCandidate::new() -> EucKrCandidate {
  {
    decoder: EucKrDecoder::new(),
    prev_byte: 0,
    prev_was_euc_range: false,
    prev: Other,
    current_word_len: 0,
    pending_score: None,
  }
}

///|
fn EucKrCandidate::maybe_set_as_pending(
  self : EucKrCandidate,
  s : Int64,
) -> Int64 {
  if self.prev == Hangul || !more_problematic_lead(self.prev_byte) {
    s
  } else {
    self.pending_score = Some(s)
    0
  }
}

///|
fn EucKrCandidate::take_pending(self : EucKrCandidate) -> Int64 {
  match self.pending_score {
    Some(pending) => {
      self.pending_score = None
      pending
    }
    None => 0
  }
}

///|
/// One more Hangul or Hanja in the current word; long words are implausible.
fn EucKrCandidate::extend_word(self : EucKrCandidate) -> Int64 {
  self.current_word_len += 1
  if self.current_word_len > 5 {
    EUC_KR_LONG_WORD_PENALTY
  } else {
    0
  }
}

///|
/// The penalty for a Hanja right after `prev`.
fn hanja_after(prev : LatinKorean) -> Int64 {
  match prev {
    AsciiLetter => CJK_LATIN_ADJACENCY_PENALTY
    Hangul => EUC_KR_HANJA_AFTER_HANGUL_PENALTY
    _ => 0
  }
}

///|
/// The score of one decoded character `u`; `in_euc_range` tells whether its
/// last byte is in 0xA1 to 0xFE.
fn EucKrCandidate::score_unit(
  self : EucKrCandidate,
  u : Int32,
  in_euc_range : Bool,
) -> Int64 {
  let mut score = 0L
  if is_ascii_letter(u) {
    // Discard pending score
    self.pending_score = None
    if self.prev is (Hangul | Hanja) {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = AsciiLetter
    self.current_word_len = 0
  } else if u >= 0xAC00 && u <= 0xD7A3 {
    score += self.take_pending()
    if self.prev_was_euc_range && in_euc_range {
      score += EUC_KR_SCORE_PER_EUC_HANGUL
      score += cjk_extra_score(u, frequent_hangul)
    } else {
      score += self.maybe_set_as_pending(EUC_KR_SCORE_PER_NON_EUC_HANGUL)
    }
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Hangul
    score += self.extend_word()
  } else if (u >= 0x4E00 && u < 0xAC00) || (u >= 0xF900 && u <= 0xFA0B) {
    score += self.take_pending()
    score += EUC_KR_SCORE_PER_HANJA
    score += hanja_after(self.prev)
    self.prev = Hanja
    score += self.extend_word()
  } else {
    if u >= 0x80 {
      score += self.take_pending()
      score += CJK_OTHER
    } else {
      // Discard pending score
      self.pending_score = None
    }
    self.prev = Other
    self.current_word_len = 0
  }
  score
}

///|
fn EucKrCandidate::feed(
  self : EucKrCandidate,
  buffer : BytesView,
  last : Bool,
) -> Int64? {
  let mut score = 0L
  for byte in buffer {
    let b = byte.to_int()
    let in_euc_range = b >= 0xA1 && b <= 0xFE
    match self.decoder.feed(b) {
      Pending => ()
      Unit(u) | Units(u, _) => score += self.score_unit(u, in_euc_range)
      Malformed(malformed_len) =>
        if (self.prev_byte == 0xC9 || self.prev_byte == 0xFE) && in_euc_range {
          score += self.take_pending()
          // The byte pair is in code page 949 EUDC range
          score += EUC_KR_PUA_PENALTY
          // Assume Hanja semantics
          score += hanja_after(self.prev)
          self.prev = Hanja
          score += self.extend_word()
        } else if (
            self.prev_byte == 0xA1 ||
            (self.prev_byte >= 0xA3 && self.prev_byte <= 0xA8) ||
            (self.prev_byte >= 0xAA && self.prev_byte <= 0xAD)
          ) &&
          b >= 0x7B &&
          b <= 0x7D {
          score += self.take_pending()
          // MacKorean symbols in range not part of code page 949
          score += EUC_KR_MAC_KOREAN_PENALTY
          self.prev = Other
          self.current_word_len = 0
        } else if self.prev_byte >= 0x81 &&
          self.prev_byte <= 0x84 &&
          (b <= 0x80 || b == 0xFF) {
          // MacKorean single-byte that conflicts with code page 949 lead
          // byte followed by ASCII or a non-conflicting single-byte
          // extension.
          self.pending_score = None
          score += EUC_KR_SINGLE_BYTE_EXTENSION_PENALTY
          if is_ascii_letter(b) {
            self.prev = AsciiLetter
          } else if b == 0x80 || b == 0xFF {
            score += EUC_KR_SINGLE_BYTE_EXTENSION_PENALTY
            self.prev = Other
          } else {
            self.prev = Other
          }
          self.current_word_len = 0
        } else if malformed_len == 1 && (b == 0x80 || b == 0xFF) {
          // MacKorean single-byte extensions that don't conflict with lead
          // bytes
          self.pending_score = None
          score += EUC_KR_SINGLE_BYTE_EXTENSION_PENALTY
          self.prev = Other
          self.current_word_len = 0
        } else {
          return None
        }
    }
    self.prev_was_euc_range = in_euc_range
    self.prev_byte = b
  }
  if last && self.decoder.incomplete() {
    return None
  }
  Some(score)
}
