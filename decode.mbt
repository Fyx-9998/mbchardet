// Decoding to text that refuses malformed input instead of replacing it.

///|
/// Why `Encoding::decode` refused its input: where the input stops being
/// valid in the encoding.
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
pub fn Encoding::decode(
  self : Encoding,
  bytes : BytesView,
) -> Result[String, DecodeError] {
  let single_byte = (index : Bytes) => {
    decode_bytes(
      self,
      bytes,
      0,
      b => {
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
      },
      () => false,
    )
  }
  match self {
    Utf8 =>
      match check_utf8(bytes) {
        Invalid(error) =>
          Err({
            encoding: self,
            valid_up_to: error.valid_up_to.to_int(),
            error_len: error.error_len,
          })
        // With no malformed sequence, decode_lossy replaces nothing.
        _ => Ok(@utf8.decode_lossy(bytes, ignore_bom=true))
      }
    Utf16Be | Utf16Le => {
      let decoder = Utf16Decoder::new(big_endian=self == Utf16Be)
      let start = match sniff_bom(bytes) {
        Some((encoding, length)) if encoding == self => length
        _ => 0
      }
      decode_bytes(self, bytes, start, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    Gbk | Gb18030 => {
      let decoder = GbkDecoder::new()
      decode_bytes(self, bytes, 0, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    Big5 => {
      let decoder = Big5Decoder::new()
      decode_bytes(self, bytes, 0, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    ShiftJis => {
      let decoder = ShiftJisDecoder::new()
      decode_bytes(self, bytes, 0, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    EucJp => {
      let decoder = EucJpDecoder::new()
      decode_bytes(self, bytes, 0, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    Iso2022Jp => {
      let decoder = Iso2022JpDecoder::new()
      decode_bytes(self, bytes, 0, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    EucKr => {
      let decoder = EucKrDecoder::new()
      decode_bytes(self, bytes, 0, b => decoder.feed(b), () => {
        decoder.incomplete()
      })
    }
    Replacement =>
      if bytes.length() == 0 {
        Ok("")
      } else {
        Err({ encoding: self, valid_up_to: 0, error_len: Some(1), })
      }
    XUserDefined =>
      decode_bytes(
        self,
        bytes,
        0,
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
/// Feeds `bytes` from `start` on to a decoder, one byte per call to `feed`,
/// and collects the text, or stops at the first malformed sequence.
/// `incomplete` tells whether the decoder is inside a sequence.
fn decode_bytes(
  encoding : Encoding,
  bytes : BytesView,
  start : Int32,
  feed : (Int32) -> Step,
  incomplete : () -> Bool,
) -> Result[String, DecodeError] {
  let text = StringBuilder(size_hint=bytes.length())
  // The offset of the first byte of the sequence being read.
  let mut first = start
  for i in start..<bytes.length() {
    if !incomplete() {
      first = i
    }
    match feed(bytes[i].to_int()) {
      Pending => ()
      Unit(unit) => text.write_char(unit.unsafe_to_char())
      Units(high, low) if high >= 0xD800 && high <= 0xDBFF =>
        text.write_char(
          (0x10000 + ((high - 0xD800) << 10) + low - 0xDC00).unsafe_to_char(),
        )
      // A Big5 letter and a combining mark.
      Units(letter, mark) => {
        text.write_char(letter.unsafe_to_char())
        text.write_char(mark.unsafe_to_char())
      }
      Malformed(length) => {
        // An ISO-2022-JP escape sequence right after another makes the
        // first one useless, and encoding_rs reports that one. Other
        // decoders report no malformed sequence of 3 bytes that starts
        // before the sequence being read.
        let valid_up_to = if encoding == Iso2022Jp && length == 3 {
          first - 3
        } else {
          first
        }
        return Err({ encoding, valid_up_to, error_len: Some(length), })
      }
    }
  }
  if incomplete() {
    return Err({ encoding, valid_up_to: first, error_len: None, })
  }
  Ok(text.to_string())
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
