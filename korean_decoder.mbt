// An EUC-KR decoder that takes one byte at a time and reports errors, for
// the EUC-KR candidate. Like the decoders in cjk_decoder.mbt it follows the
// Encoding Standard and reports each byte the way the decoder of
// encoding_rs 0.8.42 does when fed one byte per call; it starts over after a
// malformed sequence, and the ASCII byte encoding_rs keeps to read again is
// never fed to it again by chardetng's candidate.

///|
priv struct EucKrDecoder {
  // The lead byte read so far, or -1.
  mut lead : Int32
}

///|
fn EucKrDecoder::new() -> EucKrDecoder {
  { lead: -1, }
}

///|
/// Whether the end of the stream would leave a sequence incomplete.
fn EucKrDecoder::incomplete(self : EucKrDecoder) -> Bool {
  self.lead >= 0
}

///|
fn EucKrDecoder::feed(self : EucKrDecoder, b : Int32) -> Step {
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
  if b >= 0x41 && b <= 0xFE {
    let pointer = (lead - 0x81) * 190 + b - 0x41
    if 2 * pointer < euc_kr_index.length() {
      let code_point = (euc_kr_index[2 * pointer].to_int() << 8) |
        euc_kr_index[2 * pointer + 1].to_int()
      if code_point != 0 {
        return Unit(code_point)
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
