// The mbchardet command: finds the encoding of files.

///|
/// What the files are, which decides the steps that find their encoding.
priv enum Kind {
  /// Any text: a byte order mark, `--charset`, then the guess.
  Text
  /// HTML: `sniff_html`.
  Html
  /// XML: `sniff_xml`.
  Xml
}

///|
/// What the command line asks for.
priv struct Settings {
  files : Array[String]
  kind : Kind
  charset : String?
  tld : String?
  allow_utf8 : Bool
  allow_iso_2022_jp : Bool
  scores : Bool
}

///|
/// A command line that cannot be run, with the message to show.
priv suberror Usage {
  Usage(String)
}

///|
impl Show for Usage with fn output(self, logger) {
  let Usage(message) = self
  logger.write_string(message)
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "mbchardet",
    about="Finds the character encoding of each file: a byte order mark if there is one, else the guess of chardetng, the detector of Firefox. With --html or --xml, also what the document declares.",
    flags=[
      @argparse.FlagArg(
        "html",
        about="treat the files as HTML, as browsers do: after a byte order mark and --charset, the encoding a <meta> or an XML declaration in the first 1024 bytes declares, then the guess",
        conflicts_with=["xml"],
      ),
      @argparse.FlagArg(
        "xml",
        about="treat the files as XML: after a byte order mark and --charset, the encoding the XML declaration declares, else UTF-8, without guessing",
        conflicts_with=["tld", "deny-utf8", "deny-iso-2022-jp", "scores"],
      ),
      @argparse.FlagArg(
        "deny-utf8",
        about="never guess UTF-8, as browsers do for HTML from the Web",
      ),
      @argparse.FlagArg("deny-iso-2022-jp", about="never guess ISO-2022-JP"),
      @argparse.FlagArg(
        "scores",
        about="also list the score of each encoding (without the --tld hint)",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "charset",
        about="the encoding label the files came with, such as the charset of an HTTP Content-Type header; only a byte order mark overrides it",
      ),
      @argparse.OptionArg(
        "tld",
        about="the top-level domain the files came from, such as jp",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "files",
        about="the files to examine",
        num_args=@argparse.ValueRange(lower=1),
      ),
    ],
  )
}

///|
/// `tld` as `Detector::guess` takes it: in lower case, without periods and
/// in ASCII.
fn check_tld(tld : String) -> String raise Usage {
  if tld == "" || tld.contains(".") || tld.iter().any(c => c.to_int() >= 0x80) {
    raise Usage(
      "error: --tld takes the last label of the host name in ASCII, such as jp for example.co.jp or xn--p1ai for .рф; got \"\{tld}\"",
    )
  }
  tld.to_lower()
}

///|
/// `label` if it is a label of the Encoding Standard.
fn check_charset(label : String) -> String raise Usage {
  if @mbchardet.Encoding::from_label(label) is None {
    raise Usage(
      "error: --charset takes a label of the Encoding Standard, such as shift_jis or latin1; got \"\{label}\"",
    )
  }
  label
}

///|
/// The settings of the command line `argv`, without the program name.
/// Without `argv`, the command line of this process; `--help` then prints
/// the help and exits.
fn parse_args(argv? : ArrayView[String]) -> Settings raise {
  let matches = command().parse(argv?)
  let tld = match matches.values.get("tld") {
    Some([.., last]) => Some(check_tld(last))
    _ => None
  }
  let charset = match matches.values.get("charset") {
    Some([.., last]) => Some(check_charset(last))
    _ => None
  }
  let kind = if matches.flags.get_or_default("html", false) {
    Html
  } else if matches.flags.get_or_default("xml", false) {
    Xml
  } else {
    Text
  }
  {
    files: matches.values.get_or_default("files", []),
    kind,
    charset,
    tld,
    allow_utf8: !matches.flags.get_or_default("deny-utf8", false),
    allow_iso_2022_jp: !matches.flags.get_or_default("deny-iso-2022-jp", false),
    scores: matches.flags.get_or_default("scores", false),
  }
}

///|
/// One line for each encoding the detector scores, highest score first, and
/// one that lists the encodings ruled out.
fn score_lines(detector : @mbchardet.Detector) -> Array[String] {
  let scored = []
  let ruled_out = []
  for i, encoding in @mbchardet.Detector::encodings() {
    match detector.score(encoding) {
      Some(score) => scored.push((i, encoding, score))
      None => ruled_out.push(encoding.name())
    }
  }
  // Equal scores keep the order of Detector::encodings(), which is that of
  // Encoding::all().
  scored.sort_by((a, b) => {
    let by_score = b.2.compare(a.2)
    if by_score != 0 {
      by_score
    } else {
      a.0.compare(b.0)
    }
  })
  let lines = scored.map(entry => {
    let name = entry.1.name()
    "  \{name}\{" ".repeat(14 - name.length())}\{entry.2}"
  })
  if ruled_out.length() > 0 {
    lines.push("  ruled out: \{ruled_out.join(", ")}")
  }
  lines
}

///|
/// A detector that has been fed `data`, created as `settings` say.
fn detector_for(data : Bytes, settings : Settings) -> @mbchardet.Detector {
  let detector = @mbchardet.Detector::new(
    allow_iso_2022_jp=settings.allow_iso_2022_jp,
  )
  detector.feed(data[:], last=true) |> ignore
  detector
}

///|
/// The encoding of `data` and the step that decided, for any text: a byte
/// order mark, then `--charset`, then the guess. With the guess, the
/// detector that made it.
fn sniff_text(
  data : Bytes,
  settings : Settings,
) -> (@mbchardet.Sniffed, @mbchardet.Detector?) {
  if @mbchardet.sniff_bom(data[:]) is Some((encoding, _)) {
    return ({ encoding, source: ByteOrderMark, }, None)
  }
  if settings.charset is Some(label) &&
    @mbchardet.Encoding::from_label(label) is Some(encoding) {
    return ({ encoding, source: TransportLayer, }, None)
  }
  let detector = detector_for(data, settings)
  let encoding = detector.guess(
    tld?=settings.tld,
    allow_utf8=settings.allow_utf8,
  )
  ({ encoding, source: Detection, }, Some(detector))
}

///|
/// The lines printed for the file `path` that holds `data`.
fn report(path : String, data : Bytes, settings : Settings) -> Array[String] {
  let charset = settings.charset.map(label => label[:])
  let (sniffed, detector) = match settings.kind {
    Text => sniff_text(data, settings)
    Html => {
      let sniffed = @mbchardet.sniff_html(
        data[:],
        charset?,
        tld?=settings.tld,
        allow_utf8=settings.allow_utf8,
        allow_iso_2022_jp=settings.allow_iso_2022_jp,
      )
      (sniffed, None)
    }
    Xml => (@mbchardet.sniff_xml(data[:], charset?), None)
  }
  let { encoding, source, } = sniffed
  let note = match source {
    ByteOrderMark => " (byte order mark)"
    TransportLayer => " (--charset)"
    Prescan | XmlDeclaration => " (declared)"
    Default => " (default)"
    Detection =>
      if data.length() == 0 {
        " (empty)"
      } else if data.iter().all(b => b < 0x80) && encoding != Iso2022Jp {
        // Every encoding guessed then reads ASCII the same way.
        " (ASCII only)"
      } else {
        ""
      }
  }
  let lines = ["\{path}: \{encoding}\{note}"]
  if settings.scores && source == Detection {
    // sniff_html does not hand out its detector, so --html feeds another.
    let detector = match detector {
      Some(detector) => detector
      None => detector_for(data, settings)
    }
    lines.append(score_lines(detector))
  }
  lines
}

///|
fn main {
  let settings = parse_args() catch {
    error => {
      eprintln(error)
      @sys.exit(2)
      return
    }
  }
  let mut failed = false
  for path in settings.files {
    try @fs.read_file_to_bytes(path) catch {
      @fs.IOError(message) => {
        eprintln("\{path}: error: \{message}")
        failed = true
      }
    } noraise {
      data =>
        for line in report(path, data, settings) {
          println(line)
        }
    }
  }
  if failed {
    @sys.exit(1)
  }
}
