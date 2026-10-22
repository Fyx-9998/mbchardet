// GB18030 and Big5 decoders that take one byte at a time and report errors,
// for the GBK and Big5 candidates. They follow the decoders of the WHATWG
// Encoding Standard, and report each byte the way the decoders of
// encoding_rs 0.8.42 do when chardetng feeds them one byte per call: the
// UTF-16 output, or the length of a malformed sequence.
//
// After a malformed sequence encoding_rs may keep bytes to read again; these
// decoders start over instead. That gives the same answers in chardetng's
// use: its GBK candidate starts a new decoder or gives up after a malformed
// sequence, and the byte the Big5 decoder keeps is never fed to it again.

///|
/// What one byte fed to a decoder produced. The candidates read only the
/// first unit of `Units`; the decoder tests read both.
#warnings("-unused_field")
priv enum Step {
  /// The byte was consumed; a character is not complete yet.
  Pending
  /// One UTF-16 code unit.
  Unit(Int32)
  /// Two UTF-16 code units: a surrogate pair, or for Big5 a base letter and
  /// a combining mark.
  Units(Int32, Int32)
  /// A malformed sequence of that many bytes ends at this byte.
  Malformed(Int32)
}

///|
fn astral(code_point : Int32) -> Step {
  let c = code_point - 0x10000
  Units(0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF))
}

///|
/// The gb18030 decoder, which is also the GBK decoder.
priv struct GbkDecoder {
  // The bytes of the sequence read so far, or -1.
  mut first : Int32
  mut second : Int32
  mut third : Int32
}

///|
fn GbkDecoder::new() -> GbkDecoder {
  { first: -1, second: -1, third: -1, }
}

///|
fn GbkDecoder::reset(self : GbkDecoder) -> Unit {
  self.first = -1
  self.second = -1
  self.third = -1
}

///|
/// Whether the end of the stream would leave a sequence incomplete.
fn GbkDecoder::incomplete(self : GbkDecoder) -> Bool {
  self.first >= 0
}

///|
fn GbkDecoder::feed(self : GbkDecoder, b : Int32) -> Step {
  if self.first < 0 {
    if b < 0x80 {
      return Unit(b)
    }
    if b == 0x80 {
      return Unit(0x20AC)
    }
    if b == 0xFF {
      return Malformed(1)
    }
    self.first = b
    return Pending
  }
  if self.second < 0 {
    if b >= 0x30 && b <= 0x39 {
      self.second = b
      return Pending
    }
    let first = self.first
    self.reset()
    if (b >= 0x40 && b <= 0x7E) || (b >= 0x80 && b <= 0xFE) {
      let offset = if b < 0x7F { 0x40 } else { 0x41 }
      let pointer = (first - 0x81) * 190 + b - offset
      let code_unit = (gb18030_index[2 * pointer].to_int() << 8) |
        gb18030_index[2 * pointer + 1].to_int()
      return Unit(code_unit)
    }
    // An ASCII byte is not part of the malformed sequence.
    return if b < 0x80 { Malformed(1) } else { Malformed(2) }
  }
  if self.third < 0 {
    if b >= 0x81 && b <= 0xFE {
      self.third = b
      return Pending
    }
    self.reset()
    return Malformed(1)
  }
  let (first, second, third) = (self.first, self.second, self.third)
  self.reset()
  if b < 0x30 || b > 0x39 {
    return Malformed(1)
  }
  let pointer = ((first - 0x81) * 10 + second - 0x30) * (126 * 10) +
    (third - 0x81) * 10 +
    b -
    0x30
  if pointer <= 39419 {
    if pointer == 7457 {
      return Unit(0xE7C7)
    }
    return Unit(gb18030_range_decode(pointer))
  }
  if pointer >= 189000 && pointer <= 1237575 {
    return astral(pointer - 189000 + 0x10000)
  }
  Malformed(4)
}

///|
/// The code point of a four-byte pointer below 39420: the last range at or
/// below it, offset by the distance into the range.
fn gb18030_range_decode(pointer : Int32) -> Int32 {
  let mut low = 0
  let mut high = gb18030_ranges_pointers.length() - 1
  // Find the last range start that is <= pointer. The first range starts
  // at 0, so there always is one.
  while low < high {
    let mid = (low + high + 1) / 2
    if gb18030_ranges_pointers[mid] <= pointer {
      low = mid
    } else {
      high = mid - 1
    }
  }
  gb18030_ranges_code_points[low] + pointer - gb18030_ranges_pointers[low]
}

///|
priv struct Big5Decoder {
  // The lead byte read so far, or -1.
  mut lead : Int32
}

///|
fn Big5Decoder::new() -> Big5Decoder {
  { lead: -1, }
}

///|
/// Whether the end of the stream would leave a sequence incomplete.
fn Big5Decoder::incomplete(self : Big5Decoder) -> Bool {
  self.lead >= 0
}

///|
fn Big5Decoder::feed(self : Big5Decoder, b : Int32) -> Step {
  if self.lead < 0 {
    if b < 0x80 {
      return Unit(b)
    }
    if b >= 0x81 && b <= 0xFE {
      self.lead = b
      return Pending
    }
    return Malformed(1)
  }
  let lead = self.lead
  self.lead = -1
  if (b >= 0x40 && b <= 0x7E) || (b >= 0xA1 && b <= 0xFE) {
    let offset = if b < 0x7F { 0x40 } else { 0x62 }
    let pointer = (lead - 0x81) * 157 + b - offset
    match pointer {
      1133 => return Units(0x00CA, 0x0304)
      1135 => return Units(0x00CA, 0x030C)
      1164 => return Units(0x00EA, 0x0304)
      1166 => return Units(0x00EA, 0x030C)
      _ => ()
    }
    if pointer >= BIG5_FIRST_POINTER && pointer <= BIG5_LAST_POINTER {
      let i = pointer - BIG5_FIRST_POINTER
      let low = (big5_index[2 * i].to_int() << 8) |
        big5_index[2 * i + 1].to_int()
      if low != 0 {
        if ((big5_astral[i / 8].to_int() >> (i % 8)) & 1) == 1 {
          return astral(0x20000 | low)
        }
        return Unit(low)
      }
    }
  }
  // An ASCII byte is not part of the malformed sequence.
  if b < 0x80 {
    Malformed(1)
  } else {
    Malformed(2)
  }
}
