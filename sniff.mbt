// Encoding sniffing for whole documents: the encoding sniffing algorithm
// of the HTML Standard for HTML, its steps that do not read markup for
// plain text, and for XML the order of RFC 7303 (section 3.2) followed by
// the rules of XML 1.0 (section 4.3.3 and appendix F).

///|
/// The step of encoding sniffing that decided, as `sniff_text`,
/// `sniff_html` and `sniff_xml` report it.
///
/// The HTML Standard calls the encoding *certain* when a byte order mark or
/// the transport layer gave it, and *tentative* otherwise: a parser that
/// finds a `<meta>` declaring another encoding later in the document may
/// then start over with that encoding.
pub(all) enum Source {
  /// A byte order mark at the start, which is not part of the text: 3
  /// bytes for UTF-8, 2 for UTF-16BE and UTF-16LE.
  ByteOrderMark
  /// The label passed as `charset`, from the transport layer.
  TransportLayer
  /// The prescan of `prescan_html` (HTML only).
  Prescan
  /// The XML declaration (XML only).
  XmlDeclaration
  /// The guess of the detector (text and HTML).
  Detection
  /// None of the other steps: UTF-8, the default of XML (XML only).
  Default
} derive(Eq, Debug)

///|
/// The encoding that `sniff_text`, `sniff_html` or `sniff_xml` found, with
/// the step that decided.
pub(all) struct Sniffed {
  encoding : Encoding
  source : Source
} derive(Eq, Debug)

///|
/// The encoding the transport layer gives with `charset`, if it is a label.
fn transport_encoding(charset : StringView?) -> Encoding? {
  match charset {
    Some(label) => Encoding::from_label(label)
    None => None
  }
}

///|
/// The guess of a detector created with `allow_iso_2022_jp` and fed with all
/// of `bytes`.
fn detection(
  bytes : BytesView,
  tld : String?,
  allow_utf8 : Bool,
  allow_iso_2022_jp : Bool,
) -> Sniffed {
  let detector = Detector::new(allow_iso_2022_jp~)
  detector.feed(bytes, last=true) |> ignore
  { encoding: detector.guess(tld?, allow_utf8~), source: Detection, }
}

///|
/// Finds the encoding of plain text, given the text or as much of it as is
/// available. The first of these steps that applies decides:
///
/// 1. A byte order mark, as `sniff_bom` finds it.
/// 2. `charset`, the encoding label from the transport layer, as for
///    `sniff_html`.
/// 3. The guess of a `Detector` fed with all of `bytes`, created with
///    `allow_iso_2022_jp` and guessing with `tld` and `allow_utf8`.
///
/// These are the steps of `sniff_html` without the prescan: text is not
/// searched for a declaration. The defaults allow every guess, like those
/// of `Detector`.
///
/// Panics as `Detector::guess` does if `tld` contains an upper-case letter,
/// a period or a character outside ASCII.
pub fn sniff_text(
  bytes : BytesView,
  charset? : StringView,
  tld? : String,
  allow_utf8~ : Bool = true,
  allow_iso_2022_jp~ : Bool = true,
) -> Sniffed {
  if sniff_bom(bytes) is Some((encoding, _)) {
    return { encoding, source: ByteOrderMark, }
  }
  if transport_encoding(charset) is Some(encoding) {
    return { encoding, source: TransportLayer, }
  }
  detection(bytes, tld, allow_utf8, allow_iso_2022_jp)
}

///|
/// Finds the encoding of an HTML document with the encoding sniffing
/// algorithm of the HTML Standard
/// (<https://html.spec.whatwg.org/multipage/parsing.html#encoding-sniffing-algorithm>),
/// given the document or as much of it as is available. The first of these
/// steps that applies decides:
///
/// 1. A byte order mark, as `sniff_bom` finds it.
/// 2. `charset`, the encoding label from the transport layer, such as the
///    `charset` parameter of an HTTP `Content-Type` header. It counts only
///    if the Encoding Standard defines it, as `Encoding::from_label` looks
///    it up. Pass the value of the parameter: headers are not parsed here.
/// 3. The prescan of `prescan_html`, with its default limit of 1024 bytes.
/// 4. The guess of a `Detector` fed with all of `bytes`, created with
///    `allow_iso_2022_jp` and guessing with `tld` and `allow_utf8`.
///
/// The steps of the standard that depend on the browser are left out: an
/// encoding the user chose, which comes before step 2, and, before step 4,
/// the encoding of the document a frame is in and the one a page had when
/// it was last visited.
///
/// The defaults allow every guess, like those of `Detector`. To decide as a
/// browser does for a page from the Web, pass `allow_utf8=false` and
/// `allow_iso_2022_jp=false`, as chardetng's documentation advises.
///
/// Panics as `Detector::guess` does if `tld` contains an upper-case letter,
/// a period or a character outside ASCII.
pub fn sniff_html(
  bytes : BytesView,
  charset? : StringView,
  tld? : String,
  allow_utf8~ : Bool = true,
  allow_iso_2022_jp~ : Bool = true,
) -> Sniffed {
  if sniff_bom(bytes) is Some((encoding, _)) {
    return { encoding, source: ByteOrderMark, }
  }
  if transport_encoding(charset) is Some(encoding) {
    return { encoding, source: TransportLayer, }
  }
  if prescan_html(bytes) is Some(encoding) {
    return { encoding, source: Prescan, }
  }
  detection(bytes, tld, allow_utf8, allow_iso_2022_jp)
}

///|
/// Finds the encoding of an XML document, given the document or as much of
/// it as is available. RFC 7303 (section 3.2) gives the order of the first
/// two steps, and XML 1.0 (section 4.3.3 and appendix F) the others. The
/// first that applies decides:
///
/// 1. A byte order mark, as `sniff_bom` finds it.
/// 2. `charset`, the encoding label from the transport layer, as for
///    `sniff_html`.
/// 3. The XML declaration. If `bytes` starts with `<?` in UTF-16LE or
///    UTF-16BE, that encoding, as appendix F of XML 1.0 detects it.
///    Otherwise the encoding that an XML declaration at the very start of
///    `bytes`, such as `<?xml version="1.0" encoding="Shift_JIS"?>`, names,
///    if it follows the grammar of XML 1.0 (production 23, `XMLDecl`) read
///    as ASCII and names a label of the Encoding Standard. As for HTML, a
///    declared UTF-16 is taken as UTF-8, since the declaration reads as
///    ASCII.
/// 4. UTF-8, the default of XML.
///
/// Labels are looked up as the Encoding Standard says, as browsers do, so
/// `ISO-8859-1` names windows-1252. XML 1.0 also detects UTF-32 and EBCDIC,
/// which the Encoding Standard does not define; such documents get UTF-8,
/// or UTF-16LE for the UTF-32LE byte order mark, which starts with that of
/// UTF-16LE.
pub fn sniff_xml(bytes : BytesView, charset? : StringView) -> Sniffed {
  if sniff_bom(bytes) is Some((encoding, _)) {
    return { encoding, source: ByteOrderMark, }
  }
  if transport_encoding(charset) is Some(encoding) {
    return { encoding, source: TransportLayer, }
  }
  match bytes {
    [0x3C, 0x00, 0x3F, 0x00, ..] =>
      return { encoding: Utf16Le, source: XmlDeclaration, }
    [0x00, 0x3C, 0x00, 0x3F, ..] =>
      return { encoding: Utf16Be, source: XmlDeclaration, }
    _ => ()
  }
  if xml_declaration(bytes) is Some(Some(label)) {
    match Encoding::from_label(isomorphic_decode(label)) {
      Some(Utf16Be | Utf16Le) =>
        return { encoding: Utf8, source: XmlDeclaration, }
      Some(encoding) => return { encoding, source: XmlDeclaration, }
      None => ()
    }
  }
  { encoding: Utf8, source: Default, }
}
