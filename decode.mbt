// Decoding to text that refuses malformed input instead of replacing it.

///|
/// Why `Encoding::decode` or a `Decoder` refused its input: where the input
/// stops being valid in the encoding.
pub(all) struct DecodeError {
  /// The encoding the input was decoded from.
  encoding : Encoding
  /// Number of bytes before the first malformed sequence, counting a byte
  /// order mark. Those bytes decode without loss.
  valid_up_to : Int32
  /// Length in bytes of the malformed sequence that starts at `valid_up_to`,
  /// or `None` when the input ends inside a sequence that more bytes could
  /// have completed.
  ///
  /// A malformed sequence is what the decoder of the Encoding Standard turns
  /// into one U+FFFD: a byte that cannot start a character, or the bytes of
  /// a character that a later byte interrupts or that has no code point. As
  /// in `Utf8Error`, an interrupting byte is not part of it. After two
  /// ISO-2022-JP escape sequences in a row, it is the first of them.
  error_len : Int32?
} derive(Eq, Debug)

///|
/// Describes the error, for example
/// `invalid GBK: malformed sequence of 1 byte at offset 4`.
pub impl Show for DecodeError with fn output(self, logger) {
  let name = self.encoding.name()
  match self.error_len {
    _ if self.encoding == Replacement =>
      logger.write_string(
        "not decoded: the replacement encoding stands for ISO-2022-KR, ISO-2022-CN and HZ-GB-2312, whose content the Encoding Standard does not decode",
      )
    Some(len) => {
      logger.write_string("invalid \{name}: malformed sequence of \{len} byte")
      if len != 1 {
        logger.write_string("s")
      }
      logger.write_string(" at offset \{self.valid_up_to}")
    }
    None =>
      logger.write_string(
        "invalid \{name}: input ends inside a sequence that starts at offset \{self.valid_up_to}",
      )
  }
}

///|
pub extend DecodeError with Show::{to_string}

///|
/// Decodes `bytes` from this encoding, refusing instead of replacing: the
/// text if every byte sequence in `bytes` is valid, otherwise where the
/// first malformed one is. Decoders that turn malformed sequences into
/// U+FFFD lose the bytes they replace; this one never returns text with
/// such a loss.
///
/// Decoding follows the decoders of the WHATWG Encoding Standard
/// (<https://encoding.spec.whatwg.org/>) with the error mode "fatal", as
/// `TextDecoder` with `fatal: true` does. A byte order mark of this
/// encoding at the start is removed, which concerns UTF-8, UTF-16BE and
/// UTF-16LE; a mark of another encoding is decoded as content. The
/// replacement encoding decodes empty input to the empty string and refuses
/// any other.
///
/// Tests compare the text and the errors with those of encoding_rs 0.8.42.
/// For input that arrives in chunks, use a `Decoder`.
pub fn Encoding::decode(
  self : Encoding,
  bytes : BytesView,
) -> Result[String, DecodeError] {
  if self == Utf8 {
    return match check_utf8(bytes) {
      Invalid(error) =>
        Err({
          encoding: self,
          valid_up_to: error.valid_up_to.to_int(),
          error_len: error.error_len,
        })
      // With no malformed sequence, decode_lossy replaces nothing.
      _ => Ok(@utf8.decode_lossy(bytes, ignore_bom=true))
    }
  }
  let decoder = Decoder::new(self)
  match decoder.decode(bytes) {
    Ok(text) =>
      match decoder.finish() {
        Ok(_) => Ok(text)
        Err(error) => Err(error)
      }
    Err(error) => Err(error)
  }
}

///|
/// The decoder of this encoding, one byte at a time: a function that takes
/// the next byte, and one that tells whether the decoder is inside a
/// sequence, which the end of the input would cut.
fn Encoding::stepper(self : Encoding) -> ((Int32) -> Step, () -> Bool) {
  let single_byte = (index : Bytes) => {
    let feed = b => {
      if b < 0x80 {
        return Unit(b)
      }
      let code_point = (index[2 * (b - 0x80)].to_int() << 8) |
        index[2 * (b - 0x80) + 1].to_int()
      if code_point == 0 {
        Malformed(1)
      } else {
        Unit(code_point)
      }
    }
    (feed, () => false)
  }
  match self {
    Utf8 => {
      let decoder = Utf8Decoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    Utf16Be | Utf16Le => {
      let decoder = Utf16Decoder::new(big_endian=self == Utf16Be)
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    Gbk | Gb18030 => {
      let decoder = GbkDecoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    Big5 => {
      let decoder = Big5Decoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    ShiftJis => {
      let decoder = ShiftJisDecoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    EucJp => {
      let decoder = EucJpDecoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    Iso2022Jp => {
      let decoder = Iso2022JpDecoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    EucKr => {
      let decoder = EucKrDecoder::new()
      (b => decoder.feed(b), () => decoder.incomplete())
    }
    // Any byte is in error: the Encoding Standard does not decode the
    // encodings this one stands for.
    Replacement => (_ => Malformed(1), () => false)
    XUserDefined =>
      (
        b => if b < 0x80 { Unit(b) } else { Unit(0xF780 + b - 0x80) },
        () => false,
      )
    Ibm866 => single_byte(index_ibm866)
    Iso8859_2 => single_byte(index_iso_8859_2)
    Iso8859_3 => single_byte(index_iso_8859_3)
    Iso8859_4 => single_byte(index_iso_8859_4)
    Iso8859_5 => single_byte(index_iso_8859_5)
    Iso8859_6 => single_byte(index_iso_8859_6)
    Iso8859_7 => single_byte(index_iso_8859_7)
    Iso8859_8 | Iso8859_8I => single_byte(index_iso_8859_8)
    Iso8859_10 => single_byte(index_iso_8859_10)
    Iso8859_13 => single_byte(index_iso_8859_13)
    Iso8859_14 => single_byte(index_iso_8859_14)
    Iso8859_15 => single_byte(index_iso_8859_15)
    Iso8859_16 => single_byte(index_iso_8859_16)
    Koi8R => single_byte(index_koi8_r)
    Koi8U => single_byte(index_koi8_u)
    Macintosh => single_byte(index_macintosh)
    Windows874 => single_byte(index_windows_874)
    Windows1250 => single_byte(index_windows_1250)
    Windows1251 => single_byte(index_windows_1251)
    Windows1252 => single_byte(index_windows_1252)
    Windows1253 => single_byte(index_windows_1253)
    Windows1254 => single_byte(index_windows_1254)
    Windows1255 => single_byte(index_windows_1255)
    Windows1256 => single_byte(index_windows_1256)
    Windows1257 => single_byte(index_windows_1257)
    Windows1258 => single_byte(index_windows_1258)
    XMacCyrillic => single_byte(index_x_mac_cyrillic)
  }
}

///|
/// Decodes input that arrives in chunks, refusing instead of replacing, as
/// `Encoding::decode` does. A character may be split across chunks.
///
/// Pass each chunk to `decode`, which returns the text of the characters it
/// completes and keeps the bytes of an unfinished one for the next chunk,
/// then call `finish`: only the end of the input makes an unfinished
/// character an error. However the input is split, the text of the chunks
/// together and the first error are what `Encoding::decode` gives for the
/// whole input, with the offsets of an error counted from its start. The
/// call that finds an error returns only the error, not the text of its
/// chunk before it; `valid_up_to` tells where that text ends.
///
/// After an error, `decode` and `finish` return that error again.
struct Decoder {
  encoding : Encoding
  feed : (Int32) -> Step
  incomplete : () -> Bool
  // Bytes in the chunks decoded before.
  mut consumed : Int32
  // The offset of the first byte of the sequence being read.
  mut first : Int32
  // Whether no character has been written yet, while a U+FEFF would be a
  // byte order mark: for UTF-8, UTF-16BE and UTF-16LE only.
  mut before_bom : Bool
  mut error : DecodeError?
  mut finished : Bool
}

///|
/// A decoder from `encoding` that has seen no input yet.
pub fn Decoder::new(encoding : Encoding) -> Decoder {
  let (feed, incomplete) = encoding.stepper()
  {
    encoding,
    feed,
    incomplete,
    consumed: 0,
    first: 0,
    before_bom: encoding is (Utf8 | Utf16Be | Utf16Le),
    error: None,
    finished: false,
  }
}

///|
/// Writes a decoded character, unless it is the byte order mark at the start.
fn Decoder::write(
  self : Decoder,
  text : StringBuilder,
  code_point : Int32,
) -> Unit {
  if self.before_bom {
    self.before_bom = false
    if code_point == 0xFEFF {
      return
    }
  }
  text.write_char(code_point.unsafe_to_char())
}

///|
/// Decodes the next chunk of input: the text of the characters it completes,
/// or the first malformed sequence, with offsets from the start of the
/// input. The bytes of a character left unfinished at the end of the chunk
/// are kept for the next one.
///
/// Panics if called after `finish` returned `Ok`, or once the chunks reach
/// 2147483647 bytes in all, since the offsets of `DecodeError` are `Int`.
pub fn Decoder::decode(
  self : Decoder,
  chunk : BytesView,
) -> Result[String, DecodeError] {
  if self.error is Some(error) {
    return Err(error)
  }
  if self.finished {
    abort("Decoder::decode: called after finish")
  }
  if chunk.length() > 0x7FFFFFFF - self.consumed {
    abort("Decoder::decode: more than 2147483647 bytes in all")
  }
  let text = StringBuilder(size_hint=chunk.length())
  for i in 0..<chunk.length() {
    if !(self.incomplete)() {
      self.first = self.consumed + i
    }
    match (self.feed)(chunk[i].to_int()) {
      Pending => ()
      Unit(unit) => self.write(text, unit)
      Units(high, low) if high >= 0xD800 && high <= 0xDBFF =>
        self.write(text, 0x10000 + ((high - 0xD800) << 10) + low - 0xDC00)
      // A Big5 letter and a combining mark.
      Units(letter, mark) => {
        self.write(text, letter)
        self.write(text, mark)
      }
      Malformed(length) => {
        // An ISO-2022-JP escape sequence right after another makes the
        // first one useless, and encoding_rs reports that one. Other
        // decoders report no malformed sequence of 3 bytes that starts
        // before the sequence being read.
        let valid_up_to = if self.encoding == Iso2022Jp && length == 3 {
          self.first - 3
        } else {
          self.first
        }
        let error = {
          encoding: self.encoding,
          valid_up_to,
          error_len: Some(length),
        }
        self.error = Some(error)
        return Err(error)
      }
    }
  }
  self.consumed += chunk.length()
  Ok(text.to_string())
}

///|
/// Ends the input: an error if it ends inside a character, with `error_len`
/// `None`. Calling `finish` again gives the same answer.
pub fn Decoder::finish(self : Decoder) -> Result[Unit, DecodeError] {
  if self.error is Some(error) {
    return Err(error)
  }
  self.finished = true
  if (self.incomplete)() {
    let error = {
      encoding: self.encoding,
      valid_up_to: self.first,
      error_len: None,
    }
    self.error = Some(error)
    return Err(error)
  }
  Ok(())
}

///|
/// The UTF-8 decoder of the Encoding Standard, up to its first error, with
/// the checks of `Utf8Validator`.
priv struct Utf8Decoder {
  // The bits of the character read so far.
  mut code_point : Int32
  // Continuation bytes the current character needs in all, and has seen.
  mut needed : Int32
  mut seen : Int32
  // Allowed range for the next continuation byte.
  mut lower : Int32
  mut upper : Int32
}

///|
fn Utf8Decoder::new() -> Utf8Decoder {
  { code_point: 0, needed: 0, seen: 0, lower: 0x80, upper: 0xBF, }
}

///|
/// Whether the end of the stream would leave a character incomplete.
fn Utf8Decoder::incomplete(self : Utf8Decoder) -> Bool {
  self.needed != 0
}

///|
fn Utf8Decoder::feed(self : Utf8Decoder, b : Int32) -> Step {
  if self.needed == 0 {
    if b < 0x80 {
      return Unit(b)
    }
    if b >= 0xC2 && b <= 0xDF {
      self.needed = 1
      self.code_point = b & 0x1F
    } else if b >= 0xE0 && b <= 0xEF {
      // E0 would start an overlong form below A0, ED a surrogate above 9F.
      if b == 0xE0 {
        self.lower = 0xA0
      } else if b == 0xED {
        self.upper = 0x9F
      }
      self.needed = 2
      self.code_point = b & 0xF
    } else if b >= 0xF0 && b <= 0xF4 {
      // F0 would start an overlong form below 90, F4 a value above U+10FFFF
      // above 8F.
      if b == 0xF0 {
        self.lower = 0x90
      } else if b == 0xF4 {
        self.upper = 0x8F
      }
      self.needed = 3
      self.code_point = b & 0x7
    } else {
      return Malformed(1)
    }
    return Pending
  }
  if b < self.lower || b > self.upper {
    // The bytes before this one are in error, not this one.
    return Malformed(self.seen + 1)
  }
  self.lower = 0x80
  self.upper = 0xBF
  self.code_point = (self.code_point << 6) | (b & 0x3F)
  self.seen += 1
  if self.seen < self.needed {
    return Pending
  }
  self.needed = 0
  self.seen = 0
  let code_point = self.code_point
  if code_point < 0x10000 {
    Unit(code_point)
  } else {
    astral(code_point)
  }
}

///|
/// The shared UTF-16 decoder of the Encoding Standard, for UTF-16BE or
/// UTF-16LE, up to its first error.
priv struct Utf16Decoder {
  big_endian : Bool
  // The first byte of a code unit, or -1.
  mut lead_byte : Int32
  // A lead surrogate waiting for a trail surrogate, or -1.
  mut lead_surrogate : Int32
}

///|
fn Utf16Decoder::new(big_endian~ : Bool) -> Utf16Decoder {
  { big_endian, lead_byte: -1, lead_surrogate: -1, }
}

///|
/// Whether the end of the stream would leave a code unit or a surrogate
/// pair incomplete.
fn Utf16Decoder::incomplete(self : Utf16Decoder) -> Bool {
  self.lead_byte >= 0 || self.lead_surrogate >= 0
}

///|
fn Utf16Decoder::feed(self : Utf16Decoder, b : Int32) -> Step {
  if self.lead_byte < 0 {
    self.lead_byte = b
    return Pending
  }
  let unit = if self.big_endian {
    (self.lead_byte << 8) | b
  } else {
    (b << 8) | self.lead_byte
  }
  self.lead_byte = -1
  if self.lead_surrogate >= 0 {
    let lead = self.lead_surrogate
    self.lead_surrogate = -1
    if unit >= 0xDC00 && unit <= 0xDFFF {
      return Units(lead, unit)
    }
    // The lead surrogate is in error, not the code unit after it.
    return Malformed(2)
  }
  if unit >= 0xD800 && unit <= 0xDBFF {
    self.lead_surrogate = unit
    return Pending
  }
  if unit >= 0xDC00 && unit <= 0xDFFF {
    return Malformed(2)
  }
  Unit(unit)
}
