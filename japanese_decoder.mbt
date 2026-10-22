// Shift_JIS, EUC-JP and ISO-2022-JP decoders that take one byte at a time
// and report errors, for the Japanese candidates. Like the decoders in
// cjk_decoder.mbt they follow the Encoding Standard and report each byte the
// way the decoders of encoding_rs 0.8.42 do when fed one byte per call.
//
// Shift_JIS and EUC-JP start over after a malformed sequence, as encoding_rs
// does; the ASCII byte encoding_rs keeps to read again is never fed to it
// again by chardetng's candidates. ISO-2022-JP is only followed up to its
// first error, after which its candidate gives up.

///|
/// The code point of a JIS X 0208 pointer, or 0 if the index has none.
fn jis0208_code(pointer : Int32) -> Int32 {
  if pointer < 0 || 2 * pointer >= jis0208_index.length() {
    return 0
  }
  (jis0208_index[2 * pointer].to_int() << 8) |
  jis0208_index[2 * pointer + 1].to_int()
}

///|
/// The code point of a JIS X 0212 pointer, or 0 if the index has none.
fn jis0212_code(pointer : Int32) -> Int32 {
  if pointer < 0 || 2 * pointer >= jis0212_index.length() {
    return 0
  }
  (jis0212_index[2 * pointer].to_int() << 8) |
  jis0212_index[2 * pointer + 1].to_int()
}

///|
priv struct ShiftJisDecoder {
  // The lead byte read so far, or -1.
  mut lead : Int32
}

///|
fn ShiftJisDecoder::new() -> ShiftJisDecoder {
  { lead: -1, }
}

///|
/// Whether the end of the stream would leave a sequence incomplete.
fn ShiftJisDecoder::incomplete(self : ShiftJisDecoder) -> Bool {
  self.lead >= 0
}

///|
fn ShiftJisDecoder::feed(self : ShiftJisDecoder, b : Int32) -> Step {
  if self.lead < 0 {
    // ASCII, and 0x80 passes through as U+0080.
    if b <= 0x80 {
      return Unit(b)
    }
    if b >= 0xA1 && b <= 0xDF {
      // Half-width katakana
      return Unit(0xFF61 + b - 0xA1)
    }
    if (b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xFC) {
      self.lead = b
      return Pending
    }
    return Malformed(1)
  }
  let lead = self.lead
  self.lead = -1
  if (b >= 0x40 && b <= 0x7E) || (b >= 0x80 && b <= 0xFC) {
    let lead_offset = if lead < 0xA0 { 0x81 } else { 0xC1 }
    let offset = if b < 0x7F { 0x40 } else { 0x41 }
    let pointer = (lead - lead_offset) * 188 + b - offset
    if pointer >= 8836 && pointer <= 10715 {
      // User-defined characters map to the Private Use Area.
      return Unit(0xE000 - 8836 + pointer)
    }
    let code_point = jis0208_code(pointer)
    if code_point != 0 {
      return Unit(code_point)
    }
  }
  // An ASCII byte is not part of the malformed sequence.
  if b < 0x80 {
    Malformed(1)
  } else {
    Malformed(2)
  }
}

///|
priv enum EucJpPending {
  NoPending
  Jis0208Lead(Int32)
  Jis0212Shift
  Jis0212Lead(Int32)
  HalfWidthKatakana
}

///|
priv struct EucJpDecoder {
  mut pending : EucJpPending
}

///|
fn EucJpDecoder::new() -> EucJpDecoder {
  { pending: NoPending, }
}

///|
/// Whether the end of the stream would leave a sequence incomplete.
fn EucJpDecoder::incomplete(self : EucJpDecoder) -> Bool {
  !(self.pending is NoPending)
}

///|
fn EucJpDecoder::feed(self : EucJpDecoder, b : Int32) -> Step {
  let pending = self.pending
  self.pending = NoPending
  match pending {
    NoPending => {
      if b < 0x80 {
        return Unit(b)
      }
      if b >= 0xA1 && b <= 0xFE {
        self.pending = Jis0208Lead(b - 0xA1)
        return Pending
      }
      if b == 0x8F {
        self.pending = Jis0212Shift
        return Pending
      }
      if b == 0x8E {
        self.pending = HalfWidthKatakana
        return Pending
      }
      Malformed(1)
    }
    Jis0208Lead(lead) => {
      let trail = b - 0xA1
      if b < 0xA1 || b > 0xFE {
        return if b < 0x80 { Malformed(1) } else { Malformed(2) }
      }
      let code_point = jis0208_code(lead * 94 + trail)
      if code_point != 0 {
        Unit(code_point)
      } else {
        Malformed(2)
      }
    }
    Jis0212Shift => {
      if b >= 0xA1 && b <= 0xFE {
        self.pending = Jis0212Lead(b - 0xA1)
        return Pending
      }
      if b < 0x80 {
        Malformed(1)
      } else {
        Malformed(2)
      }
    }
    Jis0212Lead(lead) => {
      if b < 0xA1 || b > 0xFE {
        return if b < 0x80 { Malformed(2) } else { Malformed(3) }
      }
      let code_point = jis0212_code(lead * 94 + b - 0xA1)
      if code_point != 0 {
        Unit(code_point)
      } else {
        Malformed(3)
      }
    }
    HalfWidthKatakana => {
      if b >= 0xA1 && b <= 0xDF {
        return Unit(0xFF61 + b - 0xA1)
      }
      if b < 0x80 {
        Malformed(1)
      } else {
        Malformed(2)
      }
    }
  }
}

///|
priv enum Iso2022JpState {
  Ascii
  Roman
  Katakana
  LeadByte
  TrailByte
  EscapeStart
  Escape
} derive(Eq)

///|
/// The ISO-2022-JP decoder up to its first error.
priv struct Iso2022JpDecoder {
  mut state : Iso2022JpState
  // The state the last escape sequence selected.
  mut output_state : Iso2022JpState
  mut lead : Int32
  // Set by an escape sequence, cleared by the next byte that is not ESC.
  mut output_flag : Bool
}

///|
fn Iso2022JpDecoder::new() -> Iso2022JpDecoder {
  { state: Ascii, output_state: Ascii, lead: 0, output_flag: false, }
}

///|
/// Whether the end of the stream would be an error: inside a character or an
/// escape sequence.
fn Iso2022JpDecoder::incomplete(self : Iso2022JpDecoder) -> Bool {
  self.state is (TrailByte | EscapeStart | Escape)
}

///|
fn Iso2022JpDecoder::feed(self : Iso2022JpDecoder, b : Int32) -> Step {
  match self.state {
    Ascii | Roman => {
      if b == 0x1B {
        self.state = EscapeStart
        return Pending
      }
      self.output_flag = false
      if b > 0x7F || b == 0x0E || b == 0x0F {
        return Malformed(1)
      }
      if self.state == Roman && b == 0x5C {
        return Unit(0x00A5)
      }
      if self.state == Roman && b == 0x7E {
        return Unit(0x203E)
      }
      Unit(b)
    }
    Katakana => {
      if b == 0x1B {
        self.state = EscapeStart
        return Pending
      }
      self.output_flag = false
      if b >= 0x21 && b <= 0x5F {
        Unit(0xFF61 + b - 0x21)
      } else {
        Malformed(1)
      }
    }
    LeadByte => {
      if b == 0x1B {
        self.state = EscapeStart
        return Pending
      }
      self.output_flag = false
      if b >= 0x21 && b <= 0x7E {
        self.lead = b
        self.state = TrailByte
        Pending
      } else {
        Malformed(1)
      }
    }
    TrailByte => {
      if b == 0x1B {
        // The lead byte before the escape is in error.
        self.state = EscapeStart
        return Malformed(1)
      }
      self.state = LeadByte
      let lead = self.lead - 0x21
      let trail = b - 0x21
      if trail < 0 || trail > 0x5D {
        return Malformed(2)
      }
      let code_point = jis0208_code(lead * 94 + trail)
      if code_point != 0 {
        Unit(code_point)
      } else {
        Malformed(2)
      }
    }
    EscapeStart => {
      if b == 0x24 || b == 0x28 {
        self.lead = b
        self.state = Escape
        return Pending
      }
      self.output_flag = false
      self.state = self.output_state
      Malformed(1)
    }
    Escape => {
      let selected : Iso2022JpState? = match (self.lead, b) {
        (0x28, 0x42) => Some(Ascii)
        (0x28, 0x4A) => Some(Roman)
        (0x28, 0x49) => Some(Katakana)
        (0x24, 0x40) | (0x24, 0x42) => Some(LeadByte)
        _ => None
      }
      match selected {
        Some(state) => {
          self.lead = 0
          self.state = state
          self.output_state = state
          let flag = self.output_flag
          self.output_flag = true
          // An escape sequence right after another one makes the first one
          // useless.
          if flag {
            Malformed(3)
          } else {
            Pending
          }
        }
        None => {
          // The ESC two bytes back is in error.
          self.output_flag = false
          self.state = self.output_state
          Malformed(1)
        }
      }
    }
  }
}
