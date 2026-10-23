///|
/// An encoding of the WHATWG Encoding Standard
/// (<https://encoding.spec.whatwg.org/#names-and-labels>), which has 40.
///
/// The variants up to `Ibm866` are those `sniff_bom` and `Detector` report:
/// UTF-8 and UTF-16, and the legacy encodings chardetng can guess. The
/// variants after it only come from a label, through `Encoding::from_label`
/// or `prescan_html`.
pub(all) enum Encoding {
  Utf8
  Utf16Be
  Utf16Le
  Gbk
  Big5
  ShiftJis
  EucJp
  Iso2022Jp
  EucKr
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
  Iso8859_3
  Iso8859_8I
  Iso8859_10
  Iso8859_14
  Iso8859_15
  Iso8859_16
  Koi8R
  Macintosh
  XMacCyrillic
  Gb18030
  /// The encoding the standard maps the labels of ISO-2022-KR, HZ-GB-2312
  /// and ISO-2022-CN to. Its decoder turns any input into a single U+FFFD,
  /// so that content in these encodings is never decoded.
  Replacement
  /// x-user-defined, which maps the bytes 0x80 to 0xFF to the Private Use
  /// Area code points U+F780 to U+F7FF.
  XUserDefined
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
    Gbk => "GBK"
    Big5 => "Big5"
    ShiftJis => "Shift_JIS"
    EucJp => "EUC-JP"
    Iso2022Jp => "ISO-2022-JP"
    EucKr => "EUC-KR"
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
    Iso8859_3 => "ISO-8859-3"
    Iso8859_8I => "ISO-8859-8-I"
    Iso8859_10 => "ISO-8859-10"
    Iso8859_14 => "ISO-8859-14"
    Iso8859_15 => "ISO-8859-15"
    Iso8859_16 => "ISO-8859-16"
    Koi8R => "KOI8-R"
    Macintosh => "macintosh"
    XMacCyrillic => "x-mac-cyrillic"
    Gb18030 => "gb18030"
    Replacement => "replacement"
    XUserDefined => "x-user-defined"
  }
}

///|
/// Every encoding of the standard, in declaration order.
pub fn Encoding::all() -> Array[Encoding] {
  [
    Utf8,
    Utf16Be,
    Utf16Le,
    Gbk,
    Big5,
    ShiftJis,
    EucJp,
    Iso2022Jp,
    EucKr,
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
    Iso8859_3,
    Iso8859_8I,
    Iso8859_10,
    Iso8859_14,
    Iso8859_15,
    Iso8859_16,
    Koi8R,
    Macintosh,
    XMacCyrillic,
    Gb18030,
    Replacement,
    XUserDefined,
  ]
}

///|
/// The encoding `label` names, found as the standard's "get an encoding"
/// (<https://encoding.spec.whatwg.org/#concept-encoding-get>) finds it:
/// ASCII whitespace around the label is ignored, and so is the case of ASCII
/// letters. Returns `None` for a label the standard does not define, such
/// as `"utf-7"` or `"utf-32"`.
///
/// Many labels are other names of an encoding: `"latin1"` and `"ascii"`
/// name windows-1252, `"gb2312"` names GBK and `"utf-16"` names UTF-16LE.
pub fn Encoding::from_label(label : StringView) -> Encoding? {
  let label = label.trim(chars="\t\n\u{0C}\r ")
  let lower = StringBuilder()
  for c in label {
    lower.write_char(c.to_ascii_lowercase())
  }
  encoding_for_label(lower.to_string())
}

///|
/// Writes the canonical name, see `Encoding::name`.
pub impl Show for Encoding with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
pub extend Encoding with Show::{to_string}
