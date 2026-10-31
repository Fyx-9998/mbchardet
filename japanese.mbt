// The Shift_JIS, EUC-JP and ISO-2022-JP candidates of chardetng 1.0.0,
// ported from src/lib.rs (Apache-2.0 OR MIT, Copyright Mozilla Foundation).
// See NOTICE. The constants shared with the Chinese candidates are in
// chinese.mbt.

///|
const SHIFT_JIS_SCORE_PER_KANA : Int32 = 20

///|
const SHIFT_JIS_SCORE_PER_LEVEL_1_KANJI : Int32 = CJK_BASE_SCORE

///|
const SHIFT_JIS_SCORE_PER_LEVEL_2_KANJI : Int32 = CJK_SECONDARY_BASE_SCORE

///|
/// Manually calibrated relative to windows-1256 Persian and Urdu.
const SHIFT_JIS_INITIAL_HALF_WIDTH_KATAKANA_PENALTY : Int32 = -75

///|
const HALF_WIDTH_KATAKANA_SCORE : Int32 = 1

///|
const HALF_WIDTH_KATAKANA_VOICING_SCORE : Int32 = 10

///|
const SHIFT_JIS_PUA_PENALTY : Int32 = -(CJK_BASE_SCORE * 10)

///|
const SHIFT_JIS_EXTENSION_PENALTY : Int32 = SHIFT_JIS_PUA_PENALTY * 2

///|
const SHIFT_JIS_SINGLE_BYTE_EXTENSION_PENALTY : Int32 = SHIFT_JIS_EXTENSION_PENALTY

///|
/// Relative to Big5.
const EUC_JP_SCORE_PER_KANA : Int32 = CJK_BASE_SCORE + CJK_BASE_SCORE / 3

///|
const EUC_JP_SCORE_PER_NEAR_OBSOLETE_KANA : Int32 = CJK_BASE_SCORE - 1

///|
const EUC_JP_SCORE_PER_LEVEL_1_KANJI : Int32 = CJK_BASE_SCORE

///|
const EUC_JP_SCORE_PER_LEVEL_2_KANJI : Int32 = CJK_SECONDARY_BASE_SCORE

///|
const EUC_JP_SCORE_PER_OTHER_KANJI : Int32 = CJK_SECONDARY_BASE_SCORE / 4

///|
const EUC_JP_INITIAL_KANA_PENALTY : Int32 = -(CJK_BASE_SCORE / 3 + 1)

///|
/// Needs to be more severe than for Shift_JIS to avoid misdetecting EUC-KR.
const EUC_JP_EXTENSION_PENALTY : Int32 = -(CJK_BASE_SCORE * 50)

///|
priv enum HalfWidthKatakana {
  DakutenForbidden
  DakutenAllowed
  DakutenOrHandakutenAllowed
} derive(Eq)

///|
/// Ideographic punctuation that sets Japanese apart from Korean.
fn is_j_punctuation(u : Int32) -> Bool {
  u is (0x3000 | 0x3001 | 0x3002 | 0xFF08 | 0xFF09)
}

///|
/// Updates the voicing state for half-width katakana `u` and returns the
/// score of its voicing mark, if it is one. `state` is the state before `u`.
fn half_width_katakana_voicing(
  u : Int32,
  state : HalfWidthKatakana,
  set_state : (HalfWidthKatakana) -> Unit,
) -> Int32 {
  if (u >= 0xFF76 && u <= 0xFF84) || u == 0xFF73 {
    set_state(DakutenAllowed)
  } else if u >= 0xFF8A && u <= 0xFF8E {
    set_state(DakutenOrHandakutenAllowed)
  } else if u == 0xFF9E {
    return if state == DakutenForbidden {
      IMPLAUSIBILITY_PENALTY
    } else {
      HALF_WIDTH_KATAKANA_VOICING_SCORE
    }
  } else if u == 0xFF9F {
    return if state != DakutenOrHandakutenAllowed {
      IMPLAUSIBILITY_PENALTY
    } else {
      HALF_WIDTH_KATAKANA_VOICING_SCORE
    }
  }
  0
}

///|
priv struct ShiftJisCandidate {
  decoder : ShiftJisDecoder
  mut half_width_katakana_seen : Bool
  mut half_width_katakana_state : HalfWidthKatakana
  mut prev : LatinCj
  mut prev_byte : Int32
  mut pending_score : Int32?
}

///|
fn ShiftJisCandidate::new() -> ShiftJisCandidate {
  {
    decoder: ShiftJisDecoder::new(),
    half_width_katakana_seen: false,
    half_width_katakana_state: DakutenForbidden,
    prev: Other,
    prev_byte: 0,
    pending_score: None,
  }
}

///|
fn ShiftJisCandidate::maybe_set_as_pending(
  self : ShiftJisCandidate,
  s : Int32,
) -> Int32 {
  if self.prev == Cj || !problematic_lead(self.prev_byte) {
    s
  } else {
    self.pending_score = Some(s)
    0
  }
}

///|
fn ShiftJisCandidate::take_pending(self : ShiftJisCandidate) -> Int32 {
  match self.pending_score {
    Some(pending) => {
      self.pending_score = None
      pending
    }
    None => 0
  }
}

///|
/// The score of one decoded character `u`, `b` being its last byte.
fn ShiftJisCandidate::score_unit(
  self : ShiftJisCandidate,
  u : Int32,
  b : Int32,
) -> Int32 {
  let state = self.half_width_katakana_state
  self.half_width_katakana_state = DakutenForbidden
  let mut score = 0
  if is_ascii_letter(u) {
    // Discard pending score
    self.pending_score = None
    if self.prev == Cj {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = AsciiLetter
  } else if u >= 0xFF61 && u <= 0xFF9F {
    if !self.half_width_katakana_seen {
      self.half_width_katakana_seen = true
      // To avoid misdetecting title-length inputs
      score += SHIFT_JIS_INITIAL_HALF_WIDTH_KATAKANA_PENALTY
    }
    // Discard pending score
    self.pending_score = None
    score += HALF_WIDTH_KATAKANA_SCORE
    score += half_width_katakana_voicing(u, state, s => {
      self.half_width_katakana_state = s
    })
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else if u >= 0x3040 && u < 0x3100 {
    score += self.take_pending()
    score += SHIFT_JIS_SCORE_PER_KANA
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else if (u >= 0x3400 && u < 0xA000) || (u >= 0xF900 && u < 0xFB00) {
    score += self.take_pending()
    if self.prev_byte < 0x98 || (self.prev_byte == 0x98 && b < 0x73) {
      score += self.maybe_set_as_pending(
        SHIFT_JIS_SCORE_PER_LEVEL_1_KANJI + cjk_extra_score(u, frequent_kanji),
      )
    } else {
      score += self.maybe_set_as_pending(SHIFT_JIS_SCORE_PER_LEVEL_2_KANJI)
    }
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else if u >= 0xE000 && u < 0xF900 {
    score += self.take_pending()
    score += SHIFT_JIS_PUA_PENALTY
    self.prev = Other
  } else {
    if is_j_punctuation(u) {
      score += self.take_pending()
      // Not really needed for CJK distinction but let's give non-zero
      // score for these common byte pairs anyway.
      score += CJ_PUNCTUATION
    } else if u <= 0x7F {
      // Discard pending score
      self.pending_score = None
    } else if u == 0x80 {
      // This is a control character that overlaps euro in windows-1252
      // and happens to be a non-error in Shift_JIS.
      self.pending_score = None
      score += IMPLAUSIBILITY_PENALTY
    } else {
      score += self.take_pending()
      score += CJK_OTHER
    }
    self.prev = Other
  }
  score
}

///|
/// Pairs that are malformed in Shift_JIS but valid in Shift_JIS 2004 or
/// MacJapanese, minus those chardetng excludes.
fn is_shift_jis_extension(prev_byte : Int32, b : Int32) -> Bool {
  (
    (prev_byte >= 0x81 && prev_byte <= 0x9F) ||
    (prev_byte >= 0xE0 && prev_byte <= 0xFC)
  ) &&
  ((b >= 0x40 && b <= 0x7E) || (b >= 0x80 && b <= 0xFC)) &&
  !((prev_byte == 0x82 && b >= 0xFA) ||
  (prev_byte == 0x84 && ((b >= 0xDD && b <= 0xE4) || b >= 0xFB)) ||
  (prev_byte == 0x86 && b >= 0xF2 && b <= 0xFA) ||
  (prev_byte == 0x87 && b >= 0x77 && b <= 0x7D) ||
  (prev_byte == 0xFC && b >= 0xF5))
}

///|
fn ShiftJisCandidate::feed(
  self : ShiftJisCandidate,
  buffer : BytesView,
  last : Bool,
) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    match self.decoder.feed(b) {
      Pending => ()
      Unit(u) | Units(u, _) => score += self.score_unit(u, b)
      Malformed(malformed_len) =>
        if is_shift_jis_extension(self.prev_byte, b) {
          // Shift_JIS2004 or MacJapanese
          score += self.take_pending()
          score += SHIFT_JIS_EXTENSION_PENALTY
          // Approximate boundary
          if self.prev_byte < 0x87 {
            self.prev = Other
          } else {
            if self.prev == AsciiLetter {
              score += CJK_LATIN_ADJACENCY_PENALTY
            }
            self.prev = Cj
          }
        } else if malformed_len == 1 && (b == 0xA0 || b >= 0xFD) {
          self.pending_score = None
          score += SHIFT_JIS_SINGLE_BYTE_EXTENSION_PENALTY
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
  Some(score.to_int64())
}

///|
priv struct EucJpCandidate {
  decoder : EucJpDecoder
  mut non_ascii_seen : Bool
  mut half_width_katakana_state : HalfWidthKatakana
  mut prev : LatinCj
  mut prev_byte : Int32
  mut prev_prev_byte : Int32
}

///|
fn EucJpCandidate::new() -> EucJpCandidate {
  {
    decoder: EucJpDecoder::new(),
    non_ascii_seen: false,
    half_width_katakana_state: DakutenForbidden,
    prev: Other,
    prev_byte: 0,
    prev_prev_byte: 0,
  }
}

///|
/// The score of one decoded character `u`.
fn EucJpCandidate::score_unit(self : EucJpCandidate, u : Int32) -> Int32 {
  let state = self.half_width_katakana_state
  self.half_width_katakana_state = DakutenForbidden
  let mut score = 0
  if !self.non_ascii_seen && u >= 0x80 {
    self.non_ascii_seen = true
    if u >= 0x3040 && u < 0x3100 {
      // Remove the kana advantage over initial Big5 hanzi.
      score += EUC_JP_INITIAL_KANA_PENALTY
    }
  }
  if is_ascii_letter(u) {
    if self.prev == Cj {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = AsciiLetter
  } else if u >= 0xFF61 && u <= 0xFF9F {
    score += HALF_WIDTH_KATAKANA_SCORE
    score += half_width_katakana_voicing(u, state, s => {
      self.half_width_katakana_state = s
    })
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Other
  } else if (u >= 0x3041 && u <= 0x3093) || (u >= 0x30A1 && u <= 0x30F6) {
    if u is (0x3090 | 0x3091 | 0x30F0 | 0x30F1) {
      // Hiragana and katakana wi and we. Remove advantage over Big5 Hanzi.
      score += EUC_JP_SCORE_PER_NEAR_OBSOLETE_KANA
    } else {
      score += EUC_JP_SCORE_PER_KANA
    }
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else if (u >= 0x3400 && u < 0xA000) || (u >= 0xF900 && u < 0xFB00) {
    if self.prev_prev_byte == 0x8F {
      score += EUC_JP_SCORE_PER_OTHER_KANJI
    } else if self.prev_byte < 0xD0 {
      score += EUC_JP_SCORE_PER_LEVEL_1_KANJI
      score += cjk_extra_score(u, frequent_kanji)
    } else {
      score += EUC_JP_SCORE_PER_LEVEL_2_KANJI
    }
    if self.prev == AsciiLetter {
      score += CJK_LATIN_ADJACENCY_PENALTY
    }
    self.prev = Cj
  } else {
    if is_j_punctuation(u) {
      score += CJ_PUNCTUATION
    } else if u > 0x7F {
      score += CJK_OTHER
    }
    self.prev = Other
  }
  score
}

///|
/// Pairs in the EUC range that EUC-JP leaves unmapped but extensions use,
/// minus those chardetng excludes.
fn is_euc_jp_extension(
  prev_prev_byte : Int32,
  prev_byte : Int32,
  b : Int32,
) -> Bool {
  b >= 0xA1 &&
  b <= 0xFE &&
  prev_byte >= 0xA1 &&
  prev_byte <= 0xFE &&
  (
    (
      prev_prev_byte != 0x8F &&
      !(prev_byte == 0xA8 && b >= 0xDF && b <= 0xE6) &&
      !(prev_byte == 0xAC && b >= 0xF4 && b <= 0xFC) &&
      !(prev_byte == 0xAD && b >= 0xD8 && b <= 0xDE)
    ) ||
    (
      prev_prev_byte == 0x8F &&
      !(prev_byte is (0xA2 | 0xA6 | 0xA7 | 0xA9 | 0xAA | 0xAB | 0xED)) &&
      !(prev_byte == 0xFE && b >= 0xF7)
    )
  )
}

///|
fn EucJpCandidate::feed(
  self : EucJpCandidate,
  buffer : BytesView,
  last : Bool,
) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    match self.decoder.feed(b) {
      Pending => ()
      Unit(u) | Units(u, _) => score += self.score_unit(u)
      Malformed(_) =>
        if is_euc_jp_extension(self.prev_prev_byte, self.prev_byte, b) {
          score += EUC_JP_EXTENSION_PENALTY
          if self.prev == AsciiLetter {
            score += CJK_LATIN_ADJACENCY_PENALTY
          }
          self.prev = Cj
        } else {
          return None
        }
    }
    self.prev_prev_byte = self.prev_byte
    self.prev_byte = b
  }
  if last && self.decoder.incomplete() {
    return None
  }
  Some(score.to_int64())
}

///|
/// ISO-2022-JP scores nothing: any error rules it out.
priv struct Iso2022JpCandidate {
  decoder : Iso2022JpDecoder
}

///|
fn Iso2022JpCandidate::new() -> Iso2022JpCandidate {
  { decoder: Iso2022JpDecoder::new(), }
}

///|
fn Iso2022JpCandidate::feed(
  self : Iso2022JpCandidate,
  buffer : BytesView,
  last : Bool,
) -> Int64? {
  for byte in buffer {
    if self.decoder.feed(byte.to_int()) is Malformed(_) {
      return None
    }
  }
  if last && self.decoder.incomplete() {
    return None
  }
  Some(0)
}
