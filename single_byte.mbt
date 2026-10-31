// The single-byte candidates of chardetng 1.0.0, ported from src/lib.rs
// (Apache-2.0 OR MIT, Copyright Mozilla Foundation) and the scoring code of
// src/data.rs (CC0 1.0). See NOTICE. Names and constants follow chardetng so
// the two can be compared line by line. Scores within one call and word
// lengths are Int where chardetng uses i64 and u64: Inner::feed in
// detector.mbt keeps the scores of a call from overflowing, and the word
// lengths saturate at 2147483647 letters, which only a longer word notices.

///|
const LATIN_ADJACENCY_PENALTY : Int32 = -50

///|
const IMPLAUSIBILITY_PENALTY : Int32 = -220

///|
const ORDINAL_BONUS : Int32 = 300

///|
/// Must match the ISO-8859-2 score for " Š ".
const COPYRIGHT_BONUS : Int32 = 222

///|
const IMPLAUSIBLE_LATIN_CASE_TRANSITION_PENALTY : Int32 = -180

///|
const NON_LATIN_CAPITALIZATION_BONUS : Int32 = 40

///|
const NON_LATIN_ALL_CAPS_PENALTY : Int32 = -40

///|
const NON_LATIN_MIXED_CASE_PENALTY : Int32 = -20

///|
/// Caseless class of Latin letters.
const LATIN_LETTER : Int32 = 1

///|
/// Caseless class of ASCII digits.
const ASCII_DIGIT : Int32 = 100

///|
const WINDOWS_1256_ZWNJ : Int32 = 2

// Classes above the stored pair table, relative to its end.

///|
const PLAUSIBLE_NEXT_TO_ALPHABETIC_ON_EITHER_SIDE : Int32 = 0

///|
const IMPLAUSIBLE_NEXT_TO_ALPHABETIC_ON_EITHER_SIDE : Int32 = 1

///|
const IMPLAUSIBLE_BEFORE_ALPHABETIC : Int32 = 2

///|
const IMPLAUSIBLE_AFTER_ALPHABETIC : Int32 = 3

///|
const PLAUSIBLE_NEXT_TO_NON_ASCII_ALPHABETIC_ON_EITHER_SIDE : Int32 = 4

///|
const PLAUSIBLE_NEXT_TO_ASCII_ALPHABETIC_ON_EITHER_SIDE : Int32 = 5

///|
/// How one single-byte encoding is scored: a class for every byte, and a
/// score for every pair of classes. Bit 7 of a class marks upper case; class
/// 255 marks a byte the encoding does not use.
priv struct SingleByteData {
  id : Int32
  encoding : Encoding
  lower : Bytes
  upper : Bytes
  probabilities : Bytes
  ascii : Int32
  non_ascii : Int32
}

///|
fn SingleByteData::classify(self : SingleByteData, b : Int32) -> Int32 {
  if b < 0x80 {
    self.lower[b].to_int()
  } else {
    self.upper[b - 0x80].to_int()
  }
}

///|
fn SingleByteData::is_latin_alphabetic(
  self : SingleByteData,
  caseless_class : Int32,
) -> Bool {
  caseless_class > 0 && caseless_class < self.ascii + self.non_ascii
}

///|
fn SingleByteData::is_non_latin_alphabetic(
  self : SingleByteData,
  caseless_class : Int32,
  is_windows_1256 : Bool,
) -> Bool {
  let lower_bound = if is_windows_1256 { WINDOWS_1256_ZWNJ } else { 1 }
  caseless_class > lower_bound && caseless_class < self.ascii + self.non_ascii
}

///|
/// Index of the pair (x, y) in the pair table, or -1 for pairs the table
/// does not store.
fn compute_index(
  x : Int32,
  y : Int32,
  ascii_classes : Int32,
  non_ascii_classes : Int32,
) -> Int32 {
  if x == 0 && y == 0 {
    return -1
  }
  if x < ascii_classes && y < ascii_classes {
    return -1
  }
  if y >= ascii_classes {
    return ascii_classes * non_ascii_classes +
      (ascii_classes + non_ascii_classes) * (y - ascii_classes) +
      x
  }
  y * non_ascii_classes + x - ascii_classes
}

///|
/// The score of the class pair (`previous_class`, `current_class`).
fn SingleByteData::score(
  self : SingleByteData,
  current_class : Int32,
  previous_class : Int32,
  is_windows_1256 : Bool,
) -> Int32 {
  let stored_boundary = self.ascii + self.non_ascii
  if current_class < stored_boundary {
    if previous_class < stored_boundary {
      // Both below
      let index = compute_index(
        previous_class,
        current_class,
        self.ascii,
        self.non_ascii,
      )
      if index < 0 {
        return 0
      }
      let b = self.probabilities[index].to_int()
      if b == 255 {
        IMPLAUSIBILITY_PENALTY
      } else {
        b
      }
    } else if current_class == 0 ||
      current_class == ASCII_DIGIT ||
      (is_windows_1256 && current_class == WINDOWS_1256_ZWNJ) {
      // Current below stored, prev above. Current is space-like.
      0
    } else {
      // Current is alphabetic
      match previous_class - stored_boundary {
        PLAUSIBLE_NEXT_TO_ALPHABETIC_ON_EITHER_SIDE => 0
        IMPLAUSIBLE_NEXT_TO_ALPHABETIC_ON_EITHER_SIDE => IMPLAUSIBILITY_PENALTY
        IMPLAUSIBLE_BEFORE_ALPHABETIC => IMPLAUSIBILITY_PENALTY
        IMPLAUSIBLE_AFTER_ALPHABETIC => 0
        PLAUSIBLE_NEXT_TO_NON_ASCII_ALPHABETIC_ON_EITHER_SIDE =>
          if current_class < self.ascii {
            IMPLAUSIBILITY_PENALTY
          } else {
            0
          }
        PLAUSIBLE_NEXT_TO_ASCII_ALPHABETIC_ON_EITHER_SIDE =>
          if current_class < self.ascii {
            0
          } else {
            IMPLAUSIBILITY_PENALTY
          }
        // previous_class is ASCII_DIGIT
        _ => 0
      }
    }
  } else if previous_class < stored_boundary {
    // Current above, prev below
    if previous_class == 0 ||
      previous_class == ASCII_DIGIT ||
      (is_windows_1256 && previous_class == WINDOWS_1256_ZWNJ) {
      // Previous is space-like
      0
    } else {
      // Previous is alphabetic
      match current_class - stored_boundary {
        PLAUSIBLE_NEXT_TO_ALPHABETIC_ON_EITHER_SIDE => 0
        IMPLAUSIBLE_NEXT_TO_ALPHABETIC_ON_EITHER_SIDE => IMPLAUSIBILITY_PENALTY
        IMPLAUSIBLE_BEFORE_ALPHABETIC => 0
        IMPLAUSIBLE_AFTER_ALPHABETIC => IMPLAUSIBILITY_PENALTY
        PLAUSIBLE_NEXT_TO_NON_ASCII_ALPHABETIC_ON_EITHER_SIDE =>
          if previous_class < self.ascii {
            IMPLAUSIBILITY_PENALTY
          } else {
            0
          }
        PLAUSIBLE_NEXT_TO_ASCII_ALPHABETIC_ON_EITHER_SIDE =>
          if previous_class < self.ascii {
            0
          } else {
            IMPLAUSIBILITY_PENALTY
          }
        // current_class is ASCII_DIGIT
        _ => 0
      }
    }
  } else if current_class == ASCII_DIGIT || previous_class == ASCII_DIGIT {
    0
  } else {
    // Both above
    IMPLAUSIBILITY_PENALTY
  }
}

///|
// For Latin, we only penalize pairwise bad transitions if one participant is
// non-ASCII. This avoids violating the principle that ASCII pairs never
// contribute to the score.
priv enum LatinCaseState {
  Space
  Upper
  Lower
  AllCaps
} derive(Eq)

///|
// For non-Latin, case-related penalties and bonuses are per non-Latin word.
priv enum NonLatinCaseState {
  Space
  Upper
  Lower
  UpperLower
  AllCaps
  Mix
}

///|
priv struct NonLatinCasedCandidate {
  data : SingleByteData
  mut prev : Int32
  mut case_state : NonLatinCaseState
  mut prev_ascii : Bool
  mut current_word_len : Int32
  mut longest_word : Int32
  ibm866 : Bool
  // Only used with IBM866
  mut prev_was_a0 : Bool
}

///|
fn NonLatinCasedCandidate::new(data : SingleByteData) -> NonLatinCasedCandidate {
  {
    data,
    prev: 0,
    case_state: Space,
    prev_ascii: true,
    current_word_len: 0,
    longest_word: 0,
    ibm866: data.id == IBM866_INDEX,
    prev_was_a0: false,
  }
}

///|
fn NonLatinCasedCandidate::feed(
  self : NonLatinCasedCandidate,
  buffer : BytesView,
) -> Int64? {
  let mut score = 0
  // Grows with the length of a word, so kept apart in Int64.
  let mut word_penalties = 0L
  for byte in buffer {
    let b = byte.to_int()
    let class = self.data.classify(b)
    if class == 255 {
      return None
    }
    let caseless_class = class & 0x7F
    let ascii = b < 0x80
    let ascii_pair = self.prev_ascii && ascii
    let non_ascii_alphabetic = self.data.is_non_latin_alphabetic(
      caseless_class, false,
    )

    // This state machine avoids misdetecting Greek as Cyrillic: a small
    // bonus for words that are capitalized and lower case for the rest, a
    // per-word penalty for all-caps KOI8-U, and penalties for mixed case.
    // ASCII doesn't participate in non-Latin casing.
    if caseless_class == LATIN_LETTER {
      // Mark this word as a mess.
      self.case_state = Mix
    } else if !non_ascii_alphabetic {
      // Space
      match self.case_state {
        Space | Upper | Lower => ()
        // Intentionally applied only once per word.
        UpperLower => score += NON_LATIN_CAPITALIZATION_BONUS
        AllCaps =>
          // Intentionally applied only once per word, and only to KOI8-U.
          if self.data.id == KOI8_U_INDEX {
            score += NON_LATIN_ALL_CAPS_PENALTY
          }
        // Per letter
        Mix =>
          word_penalties += NON_LATIN_MIXED_CASE_PENALTY.to_int64() *
            self.current_word_len.to_int64()
      }
      self.case_state = Space
    } else if class >> 7 == 0 {
      // Lower case
      match self.case_state {
        Space => self.case_state = Lower
        Upper => self.case_state = UpperLower
        Lower | UpperLower | Mix => ()
        AllCaps => self.case_state = Mix
      }
    } else {
      // Upper case
      match self.case_state {
        Space => self.case_state = Upper
        Upper => self.case_state = AllCaps
        Lower | UpperLower => self.case_state = Mix
        AllCaps | Mix => ()
      }
    }
    if non_ascii_alphabetic {
      if self.current_word_len < 0x7FFFFFFF {
        self.current_word_len += 1
      }
    } else {
      if self.current_word_len > self.longest_word {
        self.longest_word = self.current_word_len
      }
      self.current_word_len = 0
    }
    let is_a0 = b == 0xA0
    if !ascii_pair {
      // 0xA0 is no-break space in many other encodings, so avoid assigning
      // score to IBM866 when 0xA0 occurs next to itself or a space-like byte.
      if !(self.ibm866 &&
        (
          (is_a0 && (self.prev_was_a0 || self.prev == 0)) ||
          (caseless_class == 0 && self.prev_was_a0)
        )) {
        score += self.data.score(caseless_class, self.prev, false)
      }
      if self.prev == LATIN_LETTER && non_ascii_alphabetic {
        score += LATIN_ADJACENCY_PENALTY
      } else if caseless_class == LATIN_LETTER &&
        self.data.is_non_latin_alphabetic(self.prev, false) {
        score += LATIN_ADJACENCY_PENALTY
      }
    }
    self.prev_ascii = ascii
    self.prev = caseless_class
    self.prev_was_a0 = is_a0
  }
  Some(score.to_int64() + word_penalties)
}

///|
priv enum OrdinalState {
  Other
  Space
  PeriodAfterN
  OrdinalExpectingSpace
  OrdinalExpectingSpaceUndoImplausibility
  OrdinalExpectingSpaceOrDigit
  OrdinalExpectingSpaceOrDigitUndoImplausibily
  UpperN
  LowerN
  FeminineAbbreviationStartLetter
  Digit
  Roman
  Copyright
}

///|
priv struct LatinCandidate {
  data : SingleByteData
  mut prev : Int32
  mut case_state : LatinCaseState
  // u32 in chardetng; Int wraps at the same points for the comparisons
  // below.
  mut prev_non_ascii : Int32
  // Used only when `windows1252` is true
  mut ordinal_state : OrdinalState
  windows1252 : Bool
}

///|
fn LatinCandidate::new(data : SingleByteData) -> LatinCandidate {
  {
    data,
    prev: 0,
    case_state: Space,
    prev_non_ascii: 0,
    ordinal_state: Space,
    windows1252: data.id == WINDOWS_1252_INDEX,
  }
}

///|
/// Caseless classes of the small Roman numerals I, V and X.
fn is_small_roman(caseless_class : Int32) -> Bool {
  caseless_class == 9 || caseless_class == 22 || caseless_class == 24
}

///|
fn LatinCandidate::feed(self : LatinCandidate, buffer : BytesView) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    let class = self.data.classify(b)
    if class == 255 {
      return None
    }
    let caseless_class = class & 0x7F
    let ascii = b < 0x80
    let ascii_pair = self.prev_non_ascii == 0 && ascii
    let non_ascii_penalty : Int32 = match self.prev_non_ascii {
      0 | 1 | 2 => 0
      3 => -5
      4 => -20
      _ => -200
    }
    score += non_ascii_penalty
    if !self.data.is_latin_alphabetic(caseless_class) {
      self.case_state = Space
    } else if class >> 7 == 0 {
      // Penalizing lower case after two upper case is important for avoiding
      // misdetecting windows-1250 as windows-1252 (byte 0x9F).
      if self.case_state == AllCaps && !ascii_pair {
        score += IMPLAUSIBLE_LATIN_CASE_TRANSITION_PENALTY
      }
      self.case_state = Lower
    } else {
      match self.case_state {
        Space => self.case_state = Upper
        Upper | AllCaps => self.case_state = AllCaps
        Lower => {
          if !ascii_pair {
            score += IMPLAUSIBLE_LATIN_CASE_TRANSITION_PENALTY
          }
          self.case_state = Upper
        }
      }
    }

    // Treat pairing space-like, which can be non-ASCII, with ASCII as
    // ASCIIish enough not to get a score in order to avoid giving ASCII i and
    // I in windows-1254 next to windows-125x apostrophe/quote a score. This
    // avoids detecting English I’ as Turkish.
    let ascii_ish_pair = ascii_pair ||
      (ascii && self.prev == 0) ||
      (caseless_class == 0 && self.prev_non_ascii == 0)
    if !ascii_ish_pair {
      score += self.data.score(caseless_class, self.prev, false)
    }
    if self.windows1252 {
      score += self.ordinal(byte, caseless_class)
    }
    if ascii {
      self.prev_non_ascii = 0
    } else {
      self.prev_non_ascii += 1
    }
    self.prev = caseless_class
  }
  Some(score.to_int64())
}

///|
/// Gives score to the windows-1252 sequences " º ", " ª ", ".ª ", ".º ",
/// "n.º1", " Mª ", " Dª ", " Nª ", " Sª " (Spanish), " 3º ", " 3ª ", " Xº ",
/// " Xª ", " Nº1", " Nº " (Italian, with an ASCII digit or a small Roman
/// numeral) and " © ", which are problematic to deal with by pairwise
/// scoring without messing up Romanian detection.
fn LatinCandidate::ordinal(
  self : LatinCandidate,
  byte : Byte,
  caseless_class : Int32,
) -> Int32 {
  let mut score = 0
  match self.ordinal_state {
    Other => if caseless_class == 0 { self.ordinal_state = Space }
    Space =>
      if caseless_class == 0 {
        ()
      } else if byte == b'\xAA' || byte == b'\xBA' {
        self.ordinal_state = OrdinalExpectingSpace
      } else if byte == b'M' || byte == b'D' || byte == b'S' {
        self.ordinal_state = FeminineAbbreviationStartLetter
      } else if byte == b'N' {
        // numero or Nuestra
        self.ordinal_state = UpperN
      } else if byte == b'n' {
        // numero
        self.ordinal_state = LowerN
      } else if caseless_class == ASCII_DIGIT {
        self.ordinal_state = Digit
      } else if is_small_roman(caseless_class) {
        self.ordinal_state = Roman
      } else if byte == b'\xA9' {
        self.ordinal_state = Copyright
      } else {
        self.ordinal_state = Other
      }
    OrdinalExpectingSpace =>
      if caseless_class == 0 {
        score += ORDINAL_BONUS
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
    OrdinalExpectingSpaceUndoImplausibility =>
      if caseless_class == 0 {
        score += ORDINAL_BONUS - IMPLAUSIBILITY_PENALTY
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
    OrdinalExpectingSpaceOrDigit =>
      if caseless_class == 0 {
        score += ORDINAL_BONUS
        self.ordinal_state = Space
      } else if caseless_class == ASCII_DIGIT {
        score += ORDINAL_BONUS
        // Deliberately set to `Other`
        self.ordinal_state = Other
      } else {
        self.ordinal_state = Other
      }
    OrdinalExpectingSpaceOrDigitUndoImplausibily =>
      if caseless_class == 0 {
        score += ORDINAL_BONUS - IMPLAUSIBILITY_PENALTY
        self.ordinal_state = Space
      } else if caseless_class == ASCII_DIGIT {
        score += ORDINAL_BONUS - IMPLAUSIBILITY_PENALTY
        // Deliberately set to `Other`
        self.ordinal_state = Other
      } else {
        self.ordinal_state = Other
      }
    UpperN =>
      if byte == b'\xAA' {
        self.ordinal_state = OrdinalExpectingSpaceUndoImplausibility
      } else if byte == b'\xBA' {
        self.ordinal_state = OrdinalExpectingSpaceOrDigitUndoImplausibily
      } else if byte == b'.' {
        self.ordinal_state = PeriodAfterN
      } else if caseless_class == 0 {
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
    LowerN =>
      if byte == b'\xBA' {
        self.ordinal_state = OrdinalExpectingSpaceOrDigitUndoImplausibily
      } else if byte == b'.' {
        self.ordinal_state = PeriodAfterN
      } else if caseless_class == 0 {
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
    FeminineAbbreviationStartLetter =>
      if byte == b'\xAA' {
        self.ordinal_state = OrdinalExpectingSpaceUndoImplausibility
      } else if caseless_class == 0 {
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
    Digit =>
      if byte == b'\xAA' || byte == b'\xBA' {
        self.ordinal_state = OrdinalExpectingSpace
      } else if caseless_class == 0 {
        self.ordinal_state = Space
      } else if caseless_class == ASCII_DIGIT {
        ()
      } else {
        self.ordinal_state = Other
      }
    Roman =>
      if byte == b'\xAA' || byte == b'\xBA' {
        self.ordinal_state = OrdinalExpectingSpaceUndoImplausibility
      } else if caseless_class == 0 {
        self.ordinal_state = Space
      } else if is_small_roman(caseless_class) {
        ()
      } else {
        self.ordinal_state = Other
      }
    PeriodAfterN =>
      if byte == b'\xBA' {
        self.ordinal_state = OrdinalExpectingSpaceOrDigit
      } else if caseless_class == 0 {
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
    Copyright =>
      if caseless_class == 0 {
        score += COPYRIGHT_BONUS
        self.ordinal_state = Space
      } else {
        self.ordinal_state = Other
      }
  }
  score
}

///|
priv struct ArabicFrenchCandidate {
  data : SingleByteData
  mut prev : Int32
  mut case_state : LatinCaseState
  mut prev_ascii : Bool
  mut current_word_len : Int32
  mut longest_word : Int32
}

///|
fn ArabicFrenchCandidate::new(data : SingleByteData) -> ArabicFrenchCandidate {
  {
    data,
    prev: 0,
    case_state: Space,
    prev_ascii: true,
    current_word_len: 0,
    longest_word: 0,
  }
}

///|
fn ArabicFrenchCandidate::feed(
  self : ArabicFrenchCandidate,
  buffer : BytesView,
) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    let class = self.data.classify(b)
    if class == 255 {
      return None
    }
    let caseless_class = class & 0x7F
    let ascii = b < 0x80
    let ascii_pair = self.prev_ascii && ascii
    if caseless_class != LATIN_LETTER {
      // We compute case penalties for French only
      self.case_state = Space
    } else if class >> 7 == 0 {
      if self.case_state == AllCaps && !ascii_pair {
        score += IMPLAUSIBLE_LATIN_CASE_TRANSITION_PENALTY
      }
      self.case_state = Lower
    } else {
      match self.case_state {
        Space => self.case_state = Upper
        Upper | AllCaps => self.case_state = AllCaps
        Lower => {
          if !ascii_pair {
            score += IMPLAUSIBLE_LATIN_CASE_TRANSITION_PENALTY
          }
          self.case_state = Upper
        }
      }
    }

    // Count only Arabic word length and ignore French
    let non_ascii_alphabetic = self.data.is_non_latin_alphabetic(
      caseless_class, true,
    )
    if non_ascii_alphabetic {
      if self.current_word_len < 0x7FFFFFFF {
        self.current_word_len += 1
      }
    } else {
      if self.current_word_len > self.longest_word {
        self.longest_word = self.current_word_len
      }
      self.current_word_len = 0
    }
    if !ascii_pair {
      score += self.data.score(caseless_class, self.prev, true)
      if self.prev == LATIN_LETTER && non_ascii_alphabetic {
        score += LATIN_ADJACENCY_PENALTY
      } else if caseless_class == LATIN_LETTER &&
        self.data.is_non_latin_alphabetic(self.prev, true) {
        score += LATIN_ADJACENCY_PENALTY
      }
    }
    self.prev_ascii = ascii
    self.prev = caseless_class
  }
  Some(score.to_int64())
}

///|
priv struct CaselessCandidate {
  data : SingleByteData
  mut prev : Int32
  mut prev_ascii : Bool
  mut current_word_len : Int32
  mut longest_word : Int32
}

///|
fn CaselessCandidate::new(data : SingleByteData) -> CaselessCandidate {
  { data, prev: 0, prev_ascii: true, current_word_len: 0, longest_word: 0, }
}

///|
fn CaselessCandidate::feed(
  self : CaselessCandidate,
  buffer : BytesView,
) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    let class = self.data.classify(b)
    if class == 255 {
      return None
    }
    let caseless_class = class & 0x7F
    let ascii = b < 0x80
    let ascii_pair = self.prev_ascii && ascii
    let non_ascii_alphabetic = self.data.is_non_latin_alphabetic(
      caseless_class, false,
    )
    if non_ascii_alphabetic {
      if self.current_word_len < 0x7FFFFFFF {
        self.current_word_len += 1
      }
    } else {
      if self.current_word_len > self.longest_word {
        self.longest_word = self.current_word_len
      }
      self.current_word_len = 0
    }
    if !ascii_pair {
      score += self.data.score(caseless_class, self.prev, false)
      if self.prev == LATIN_LETTER && non_ascii_alphabetic {
        score += LATIN_ADJACENCY_PENALTY
      } else if caseless_class == LATIN_LETTER &&
        self.data.is_non_latin_alphabetic(self.prev, false) {
        score += LATIN_ADJACENCY_PENALTY
      }
    }
    self.prev_ascii = ascii
    self.prev = caseless_class
  }
  Some(score.to_int64())
}

///|
/// Whether `byte` is one of the punctuation marks chardetng counts to tell
/// logical from visual Hebrew.
fn is_ascii_punctuation(byte : Byte) -> Bool {
  byte is (b'.' | b',' | b':' | b';' | b'?' | b'!')
}

///|
/// Hebrew in logical order (windows-1255).
priv struct LogicalCandidate {
  data : SingleByteData
  mut prev : Int32
  mut prev_ascii : Bool
  // Punctuation right after a Hebrew letter, as logical order puts it.
  mut plausible_punctuation : Int64
  mut current_word_len : Int32
  mut longest_word : Int32
}

///|
fn LogicalCandidate::new(data : SingleByteData) -> LogicalCandidate {
  {
    data,
    prev: 0,
    prev_ascii: true,
    plausible_punctuation: 0,
    current_word_len: 0,
    longest_word: 0,
  }
}

///|
fn LogicalCandidate::feed(
  self : LogicalCandidate,
  buffer : BytesView,
) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    let class = self.data.classify(b)
    if class == 255 {
      return None
    }
    let caseless_class = class & 0x7F
    let ascii = b < 0x80
    let ascii_pair = self.prev_ascii && ascii
    let non_ascii_alphabetic = self.data.is_non_latin_alphabetic(
      caseless_class, false,
    )
    if non_ascii_alphabetic {
      if self.current_word_len < 0x7FFFFFFF {
        self.current_word_len += 1
      }
    } else {
      if self.current_word_len > self.longest_word {
        self.longest_word = self.current_word_len
      }
      self.current_word_len = 0
    }
    if !ascii_pair {
      score += self.data.score(caseless_class, self.prev, false)
      let prev_non_ascii_alphabetic = self.data.is_non_latin_alphabetic(
        self.prev,
        false,
      )
      if caseless_class == 0 &&
        prev_non_ascii_alphabetic &&
        is_ascii_punctuation(byte) {
        self.plausible_punctuation += 1
      }
      if self.prev == LATIN_LETTER && non_ascii_alphabetic {
        score += LATIN_ADJACENCY_PENALTY
      } else if caseless_class == LATIN_LETTER && prev_non_ascii_alphabetic {
        score += LATIN_ADJACENCY_PENALTY
      }
    }
    self.prev_ascii = ascii
    self.prev = caseless_class
  }
  Some(score.to_int64())
}

///|
/// Hebrew in visual order (ISO-8859-8).
priv struct VisualCandidate {
  data : SingleByteData
  mut prev : Int32
  mut prev_ascii : Bool
  mut prev_punctuation : Bool
  // Hebrew letters right after punctuation, as visual order puts them.
  mut plausible_punctuation : Int64
  mut current_word_len : Int32
  mut longest_word : Int32
}

///|
fn VisualCandidate::new(data : SingleByteData) -> VisualCandidate {
  {
    data,
    prev: 0,
    prev_ascii: true,
    prev_punctuation: false,
    plausible_punctuation: 0,
    current_word_len: 0,
    longest_word: 0,
  }
}

///|
fn VisualCandidate::feed(self : VisualCandidate, buffer : BytesView) -> Int64? {
  let mut score = 0
  for byte in buffer {
    let b = byte.to_int()
    let class = self.data.classify(b)
    if class == 255 {
      return None
    }
    let caseless_class = class & 0x7F
    let ascii = b < 0x80
    let ascii_pair = self.prev_ascii && ascii
    let non_ascii_alphabetic = self.data.is_non_latin_alphabetic(
      caseless_class, false,
    )
    if non_ascii_alphabetic {
      if self.current_word_len < 0x7FFFFFFF {
        self.current_word_len += 1
      }
    } else {
      if self.current_word_len > self.longest_word {
        self.longest_word = self.current_word_len
      }
      self.current_word_len = 0
    }
    if !ascii_pair {
      score += self.data.score(caseless_class, self.prev, false)
      if non_ascii_alphabetic && self.prev_punctuation {
        self.plausible_punctuation += 1
      }
      if self.prev == LATIN_LETTER && non_ascii_alphabetic {
        score += LATIN_ADJACENCY_PENALTY
      } else if caseless_class == LATIN_LETTER &&
        self.data.is_non_latin_alphabetic(self.prev, false) {
        score += LATIN_ADJACENCY_PENALTY
      }
    }
    self.prev_ascii = ascii
    self.prev = caseless_class
    self.prev_punctuation = caseless_class == 0 && is_ascii_punctuation(byte)
  }
  Some(score.to_int64())
}
