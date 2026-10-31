// The mbchardet command: finds the encoding of files, and converts a file
// to UTF-8.

///|
/// What the files are, which decides the steps that find their encoding.
priv enum Kind {
  /// Any text: `sniff_text`.
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
  /// Where to write the only file in UTF-8.
  output : String?
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
    about="Finds the character encoding of each file: a byte order mark if there is one, else the guess of chardetng, the detector of Firefox. With --html or --xml, also what the document declares. With --output, also converts the file to UTF-8, unless a byte sequence in it is not valid in that encoding.",
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
      @argparse.OptionArg(
        "output",
        short='o',
        about="write the only file to this path in UTF-8, without a byte order mark; nothing is written if a byte sequence in the file is not valid in the encoding found. Not with --html or --xml: the converted document would still declare its old encoding",
        conflicts_with=["html", "xml"],
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
  let files = matches.values.get_or_default("files", [])
  let output = match matches.values.get("output") {
    Some([.., last]) => Some(last)
    _ => None
  }
  if output is Some(_) && files.length() != 1 {
    raise Usage(
      "error: --output takes the text of one file; got \{files.length()} files",
    )
  }
  {
    files,
    kind,
    charset,
    tld,
    allow_utf8: !matches.flags.get_or_default("deny-utf8", false),
    allow_iso_2022_jp: !matches.flags.get_or_default("deny-iso-2022-jp", false),
    scores: matches.flags.get_or_default("scores", false),
    output,
  }
}

///|
/// One line for each encoding the detector scores, highest score first, and
/// one that lists the encodings ruled out.
fn score_lines(detector : @mbchardet.Detector) -> Array[String] {
  let lines = detector
    .scores()
    .map(entry => {
      let name = entry.0.name()
      "  \{name}\{" ".repeat(14 - name.length())}\{entry.1}"
    })
  let ruled_out = @mbchardet.Detector::encodings()
    .filter(encoding => detector.score(encoding) is None)
    .map(encoding => encoding.name())
  if ruled_out.length() > 0 {
    lines.push("  ruled out: \{ruled_out.join(", ")}")
  }
  lines
}

///|
/// The lines printed for the file `path` that holds `data`, and the
/// encoding found.
fn examine(
  path : String,
  data : Bytes,
  settings : Settings,
) -> (Array[String], @mbchardet.Encoding) {
  let charset = settings.charset.map(label => label[:])
  let sniffed = match settings.kind {
    Text =>
      @mbchardet.sniff_text(
        data,
        charset?,
        tld?=settings.tld,
        allow_utf8=settings.allow_utf8,
        allow_iso_2022_jp=settings.allow_iso_2022_jp,
      )
    Html =>
      @mbchardet.sniff_html(
        data,
        charset?,
        tld?=settings.tld,
        allow_utf8=settings.allow_utf8,
        allow_iso_2022_jp=settings.allow_iso_2022_jp,
      )
    Xml => @mbchardet.sniff_xml(data, charset?)
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
    // The sniffing functions keep their detector, so the scores come from
    // another, fed the same way.
    let detector = @mbchardet.Detector::new(
      allow_iso_2022_jp=settings.allow_iso_2022_jp,
    )
    detector.feed(data, last=true) |> ignore
    lines.append(score_lines(detector))
  }
  (lines, encoding)
}

///|
/// `data` converted from `encoding` to UTF-8, or why it cannot be, with the
/// bytes in error.
fn convert(
  data : Bytes,
  encoding : @mbchardet.Encoding,
) -> Result[Bytes, String] {
  match encoding.decode(data) {
    Ok(text) => Ok(@utf8.encode(text))
    Err(error) if encoding == Replacement => Err(error.to_string())
    Err(error) => {
      // Within `data`, which a Bytes holds, so the offset fits an Int.
      let start = error.valid_up_to.to_int()
      let end = match error.error_len {
        Some(length) => start + length
        None => data.length()
      }
      let bytes = data[start:end]
        .iter()
        .map(b => b.to_int().to_string(radix=16).to_upper().pad_start(2, '0'))
        .join(" ")
      Err("\{error} (\{bytes})")
    }
  }
}

///|
/// Writes `data`, the file `path` in `encoding`, to `output` in UTF-8, and
/// reports it. Returns false, without writing, if `data` is not valid in
/// `encoding` or cannot be written.
fn write_converted(
  path : String,
  data : Bytes,
  encoding : @mbchardet.Encoding,
  output : String,
) -> Bool {
  match convert(data, encoding) {
    Ok(utf8) =>
      try @fs.write_bytes_to_file(output, utf8) catch {
        @fs.IOError(message) => {
          eprintln("\{output}: error: \{message}")
          false
        }
      } noraise {
        _ => {
          println("\{output}: UTF-8 (converted from \{path})")
          true
        }
      }
    Err(message) => {
      eprintln("\{path}: error: \{message}; \{output} not written")
      false
    }
  }
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
      data => {
        let (lines, encoding) = examine(path, data, settings)
        for line in lines {
          println(line)
        }
        if settings.output is Some(output) &&
          !write_converted(path, data, encoding, output) {
          failed = true
        }
      }
    }
  }
  if failed {
    @sys.exit(1)
  }
}
