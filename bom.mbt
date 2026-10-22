///|
/// Looks for a byte order mark at the start of `bytes`, like the "BOM sniff"
/// step of the WHATWG Encoding Standard
/// (<https://encoding.spec.whatwg.org/#bom-sniff>).
///
/// Returns the encoding the mark selects together with the length of the mark
/// in bytes, or `None` when `bytes` does not start with a mark:
///
/// - `EF BB BF` gives `(Utf8, 3)`
/// - `FE FF` gives `(Utf16Be, 2)`
/// - `FF FE` gives `(Utf16Le, 2)`
///
/// The check follows the standard exactly, so the UTF-32LE mark `FF FE 00 00`
/// is reported as UTF-16LE. mbchardet does not support UTF-32.
pub fn sniff_bom(bytes : BytesView) -> (Encoding, Int32)? {
  match bytes {
    [0xEF, 0xBB, 0xBF, ..] => Some((Utf8, 3))
    [0xFE, 0xFF, ..] => Some((Utf16Be, 2))
    [0xFF, 0xFE, ..] => Some((Utf16Le, 2))
    _ => None
  }
}
