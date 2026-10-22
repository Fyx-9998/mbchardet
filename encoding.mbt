///|
/// An encoding mbchardet can report.
pub(all) enum Encoding {
  Utf8
  Utf16Be
  Utf16Le
  Windows874
  Windows1250
  Windows1251
  Windows1252
  Windows1253
  Windows1254
  Windows1255
  Windows1256
  Windows1257
  Windows1258
  Iso8859_2
  Iso8859_4
  Iso8859_5
  Iso8859_6
  Iso8859_7
  Iso8859_8
  Iso8859_13
  Koi8U
  Ibm866
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
    Windows874 => "windows-874"
    Windows1250 => "windows-1250"
    Windows1251 => "windows-1251"
    Windows1252 => "windows-1252"
    Windows1253 => "windows-1253"
    Windows1254 => "windows-1254"
    Windows1255 => "windows-1255"
    Windows1256 => "windows-1256"
    Windows1257 => "windows-1257"
    Windows1258 => "windows-1258"
    Iso8859_2 => "ISO-8859-2"
    Iso8859_4 => "ISO-8859-4"
    Iso8859_5 => "ISO-8859-5"
    Iso8859_6 => "ISO-8859-6"
    Iso8859_7 => "ISO-8859-7"
    Iso8859_8 => "ISO-8859-8"
    Iso8859_13 => "ISO-8859-13"
    Koi8U => "KOI8-U"
    Ibm866 => "IBM866"
  }
}

///|
/// Every encoding mbchardet can report, in declaration order.
pub fn Encoding::all() -> Array[Encoding] {
  [
    Utf8,
    Utf16Be,
    Utf16Le,
    Windows874,
    Windows1250,
    Windows1251,
    Windows1252,
    Windows1253,
    Windows1254,
    Windows1255,
    Windows1256,
    Windows1257,
    Windows1258,
    Iso8859_2,
    Iso8859_4,
    Iso8859_5,
    Iso8859_6,
    Iso8859_7,
    Iso8859_8,
    Iso8859_13,
    Koi8U,
    Ibm866,
  ]
}

///|
/// Writes the canonical name, see `Encoding::name`.
pub impl Show for Encoding with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
pub extend Encoding with Show::{to_string}
