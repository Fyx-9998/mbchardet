///|
/// Where and why an input stops being valid UTF-8.
pub(all) struct Utf8Error {
  /// Number of bytes before the first malformed sequence. Those bytes are
  /// valid UTF-8.
  valid_up_to : Int64
  /// Length in bytes of the malformed sequence that starts at `valid_up_to`,
  /// or `None` when the input ends inside a sequence that more bytes could
  /// have completed.
  ///
  /// A malformed sequence is either a single byte that cannot start a
  /// character, or the bytes of a character that a later byte interrupts (at
  /// most 3). The interrupting byte is not part of it. This is the unit the
  /// UTF-8 decoder of the WHATWG Encoding Standard replaces with one U+FFFD.
  error_len : Int32?
} derive(Eq, Debug)

///|
/// Describes the error, for example
/// `invalid UTF-8: malformed sequence of 1 byte at offset 4`.
pub impl Show for Utf8Error with fn output(self, logger) {
  match self.error_len {
    Some(len) => {
      logger.write_string("invalid UTF-8: malformed sequence of \{len} byte")
      if len != 1 {
        logger.write_string("s")
      }
      logger.write_string(" at offset \{self.valid_up_to}")
    }
    None =>
      logger.write_string(
        "invalid UTF-8: input ends inside a character that starts at offset \{self.valid_up_to}",
      )
  }
}

///|
pub extend Utf8Error with Show::{to_string}

///|
/// The result of checking whether bytes are UTF-8.
pub(all) enum Utf8Status {
  /// Every byte is below 0x80. The bytes are valid UTF-8, and also valid in
  /// every encoding that is a superset of ASCII, so they say nothing about
  /// which of those encodings was meant.
  AsciiOnly
  /// Valid UTF-8 with at least one character outside ASCII.
  Valid
  /// Not valid UTF-8.
  Invalid(Utf8Error)
} derive(Eq, Debug)

///|
/// Checks UTF-8 validity of input that arrives in chunks, without decoding
/// it. A character may be split across chunks.
///
/// Validity follows the UTF-8 decoder of the WHATWG Encoding Standard
/// (<https://encoding.spec.whatwg.org/#utf-8-decoder>): overlong forms,
/// surrogates (U+D800 to U+DFFF) and values above U+10FFFF are errors. A byte
/// order mark is an ordinary character here; see `sniff_bom` to recognize it.
struct Utf8Validator {
  // Bytes fed before the current chunk.
  mut consumed : Int64
  // Continuation bytes the current character needs in all, and has seen.
  mut needed : Int32
  mut seen : Int32
  // Allowed range for the next continuation byte.
  mut lower : Int32
  mut upper : Int32
  // Offset of the lead byte of the current character.
  mut start : Int64
  mut non_ascii : Bool
  mut error : Utf8Error?
}

///|
/// A validator that has seen no input yet.
pub fn Utf8Validator::new() -> Utf8Validator {
  {
    consumed: 0,
    needed: 0,
    seen: 0,
    lower: 0x80,
    upper: 0xBF,
    start: 0,
    non_ascii: false,
    error: None,
  }
}

///|
/// Checks the next chunk of input. Returns `false` once an error has been
/// found, in this chunk or an earlier one; later chunks are then ignored and
/// `finish` reports the first error.
///
/// A character left incomplete at the end of the chunk is not an error yet:
/// the next chunk may complete it.
pub fn Utf8Validator::feed(self : Utf8Validator, chunk : BytesView) -> Bool {
  if self.error is Some(_) {
    return false
  }
  for i in 0..<chunk.length() {
    let b = chunk[i].to_int()
    if self.needed == 0 {
      if b < 0x80 {
        continue
      }
      self.non_ascii = true
      self.start = self.consumed + i.to_int64()
      if b >= 0xC2 && b <= 0xDF {
        self.needed = 1
      } else if b >= 0xE0 && b <= 0xEF {
        // E0 would start an overlong form below A0, ED a surrogate above 9F.
        if b == 0xE0 {
          self.lower = 0xA0
        } else if b == 0xED {
          self.upper = 0x9F
        }
        self.needed = 2
      } else if b >= 0xF0 && b <= 0xF4 {
        // F0 would start an overlong form below 90, F4 a value above
        // U+10FFFF above 8F.
        if b == 0xF0 {
          self.lower = 0x90
        } else if b == 0xF4 {
          self.upper = 0x8F
        }
        self.needed = 3
      } else {
        self.error = Some({ valid_up_to: self.start, error_len: Some(1), })
        return false
      }
    } else if b < self.lower || b > self.upper {
      self.error = Some({
        valid_up_to: self.start,
        error_len: Some(self.seen + 1),
      })
      return false
    } else {
      self.lower = 0x80
      self.upper = 0xBF
      self.seen += 1
      if self.seen == self.needed {
        self.needed = 0
        self.seen = 0
      }
    }
  }
  self.consumed += chunk.length().to_int64()
  true
}

///|
/// The status of all input fed so far, treating its end as the end of the
/// input: a character still incomplete is an error with `error_len` `None`.
///
/// `finish` does not change the validator. Feeding more input afterwards
/// continues where the last chunk ended.
pub fn Utf8Validator::finish(self : Utf8Validator) -> Utf8Status {
  match self.error {
    Some(error) => Invalid(error)
    None =>
      if self.needed != 0 {
        Invalid({ valid_up_to: self.start, error_len: None, })
      } else if self.non_ascii {
        Valid
      } else {
        AsciiOnly
      }
  }
}

///|
/// Checks whether `bytes`, taken as a complete input, are UTF-8. The same as
/// feeding them to a new `Utf8Validator` in one chunk and calling `finish`.
pub fn check_utf8(bytes : BytesView) -> Utf8Status {
  let validator = Utf8Validator::new()
  validator.feed(bytes) |> ignore
  validator.finish()
}
