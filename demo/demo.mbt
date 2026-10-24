// The functions the browser demo (index.html and app.js) calls. Each takes
// the bytes of a file and returns its answer as a JSON string.

///|
/// The text of `data` in `encoding` as JSON: `{"text": ..., "error": null}`,
/// or `{"text": null, "error": {...}}` with the message, the offset of the
/// first malformed sequence and its length (null if the input ends inside
/// it).
fn decoded_json(data : Bytes, encoding : @mbchardet.Encoding) -> Json {
  match encoding.decode(data[:]) {
    Ok(text) => { "text": Json::string(text), "error": Json::null() }
    Err(error) =>
      {
        "text": Json::null(),
        "error": {
          "message": Json::string(error.to_string()),
          "offset": Json::number(error.valid_up_to.to_double()),
          "length": match error.error_len {
            Some(length) => Json::number(length.to_double())
            None => Json::null()
          },
        },
      }
  }
}

///|
/// The scores of the detector, highest first and in the order of
/// `Detector::encodings()` when equal, and the encodings it ruled out.
fn scores_json(detector : @mbchardet.Detector) -> (Json, Json) {
  let scored = []
  let ruled_out = []
  for i, encoding in @mbchardet.Detector::encodings() {
    match detector.score(encoding) {
      Some(score) => scored.push((i, encoding, score))
      None => ruled_out.push(Json::string(encoding.name()))
    }
  }
  scored.sort_by((a, b) => {
    let by_score = b.2.compare(a.2)
    if by_score != 0 {
      by_score
    } else {
      a.0.compare(b.0)
    }
  })
  let scores : Array[Json] = scored.map(entry => {
    "encoding": Json::string(entry.1.name()),
    "score": Json::number(entry.2.to_double()),
  })
  (Json::array(scores), Json::array(ruled_out))
}

///|
/// Why an option of the page cannot be used, if it cannot: `charset` must be
/// empty or a label, `tld` empty or the last label of a host name in ASCII.
fn problem(charset : String, tld : String) -> String? {
  if charset != "" && @mbchardet.Encoding::from_label(charset) is None {
    return Some(
      "\"\{charset}\" is not a label of the Encoding Standard, such as shift_jis or latin1",
    )
  }
  if tld.contains(".") || tld.iter().any(c => c.to_int() >= 0x80) {
    return Some(
      "the top-level domain is the last label of the host name in ASCII, such as jp for example.co.jp or xn--p1ai for .рф; got \"\{tld}\"",
    )
  }
  None
}

///|
/// What the page shows for the file `data`, as a JSON string.
///
/// `mode` is `"html"` or `"xml"` to find the encoding as `sniff_html` or
/// `sniff_xml` does, anything else for plain text: a byte order mark, then
/// `charset`, then the guess. `charset` and `tld` are empty when not given;
/// an empty `charset` is no label.
///
/// The result has `problem`, a message when an option cannot be used and
/// null otherwise. Without a problem, it also has `encoding`, its name;
/// `source`, the step that decided (`"bom"`, `"charset"`, `"declared"`,
/// `"detection"` or `"default"`); `ascii`, whether every byte is below 0x80;
/// `scores` and `ruled_out`, the detector's scores highest first and the
/// encodings it ruled out, both null for XML, which is not guessed; and
/// `decoded`, as `decode_as` gives it for the encoding found.
pub fn examine(
  data : Bytes,
  mode : String,
  charset : String,
  tld : String,
  allow_utf8 : Bool,
  allow_iso_2022_jp : Bool,
) -> String {
  if problem(charset, tld) is Some(message) {
    let result : Json = { "problem": Json::string(message) }
    return result.stringify()
  }
  let tld = if tld == "" { None } else { Some(tld.to_lower()) }
  let detector = if mode == "xml" {
    None
  } else {
    let detector = @mbchardet.Detector::new(allow_iso_2022_jp~)
    detector.feed(data[:], last=true) |> ignore
    Some(detector)
  }
  let sniffed : @mbchardet.Sniffed = match mode {
    "html" =>
      @mbchardet.sniff_html(
        data[:],
        charset~,
        tld?,
        allow_utf8~,
        allow_iso_2022_jp~,
      )
    "xml" => @mbchardet.sniff_xml(data[:], charset~)
    // Plain text, as the command-line tool finds its encoding.
    _ =>
      if @mbchardet.sniff_bom(data[:]) is Some((encoding, _)) {
        { encoding, source: ByteOrderMark, }
      } else if @mbchardet.Encoding::from_label(charset) is Some(encoding) {
        { encoding, source: TransportLayer, }
      } else {
        let encoding = detector.unwrap().guess(tld?, allow_utf8~)
        { encoding, source: Detection, }
      }
  }
  let source = match sniffed.source {
    ByteOrderMark => "bom"
    TransportLayer => "charset"
    Prescan | XmlDeclaration => "declared"
    Detection => "detection"
    Default => "default"
  }
  let (scores, ruled_out) = match detector {
    Some(detector) => scores_json(detector)
    None => (Json::null(), Json::null())
  }
  let result : Json = {
    "problem": Json::null(),
    "encoding": Json::string(sniffed.encoding.name()),
    "source": Json::string(source),
    "ascii": Json::boolean(data.iter().all(b => b < 0x80)),
    "scores": scores,
    "ruled_out": ruled_out,
    "decoded": decoded_json(data, sniffed.encoding),
  }
  result.stringify()
}

///|
/// The text of `data` in the encoding named `name`, as JSON:
/// `{"text": ..., "error": null}`, or `{"text": null, "error": {"message",
/// "offset", "length"}}`, where `length` is null if the input ends inside
/// the malformed sequence. An unknown name gives `{"text": null, "error":
/// null}`.
pub fn decode_as(data : Bytes, name : String) -> String {
  let result : Json = match @mbchardet.Encoding::from_label(name) {
    Some(encoding) => decoded_json(data, encoding)
    None => { "text": Json::null(), "error": Json::null() }
  }
  result.stringify()
}

///|
/// The names of the 40 encodings, as a JSON array in the order of
/// `Encoding::all()`.
pub fn encoding_names() -> String {
  Json::array(@mbchardet.Encoding::all().map(e => Json::string(e.name()))).stringify()
}
