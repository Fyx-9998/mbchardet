///|
/// An encoding mbchardet can report.
pub(all) enum Encoding {
  Utf8
  Utf16Be
  Utf16Le
} derive(Eq, Hash, Debug)

///|
/// The canonical name of the encoding in the WHATWG Encoding Standard
/// (<https://encoding.spec.whatwg.org/#names-and-labels>). Every name is also
/// a valid label, so it can be passed to a decoder that follows the standard.
pub fn Encoding::name(self : Encoding) -> String {
  match self {
    Utf8 => "UTF-8"
    Utf16Be => "UTF-16BE"
    Utf16Le => "UTF-16LE"
  }
}

///|
/// Writes the canonical name, see `Encoding::name`.
pub impl Show for Encoding with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
pub extend Encoding with Show::{to_string}
