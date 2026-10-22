// The mbchardet command: guesses the encoding of files.

///|
/// What the command line asks for.
priv struct Settings {
  files : Array[String]
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
    about="Guesses the character encoding of each file: a byte order mark if there is one, else the guess of chardetng, the detector of Firefox.",
    flags=[
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
/// The settings of the command line `argv`, without the program name.
/// Without `argv`, the command line of this process; `--help` then prints
/// the help and exits.
fn parse_args(argv? : ArrayView[String]) -> Settings raise {
  let matches = command().parse(argv?)
  let tld = match matches.values.get("tld") {
    Some([.., last]) => Some(check_tld(last))
    _ => None
  }
  {
    files: matches.values.get_or_default("files", []),
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
  for i, encoding in @mbchardet.Encoding::all() {
    // Only a byte order mark identifies UTF-16.
    if encoding is (Utf16Be | Utf16Le) {
      continue
    }
    match detector.score(encoding) {
      Some(score) => scored.push((i, encoding, score))
      None => ruled_out.push(encoding.name())
    }
  }
  // Equal scores keep the order of Encoding::all().
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
/// The lines printed for the file `path` that holds `data`.
fn report(path : String, data : Bytes, settings : Settings) -> Array[String] {
  if @mbchardet.sniff_bom(data[:]) is Some((encoding, _)) {
    return ["\{path}: \{encoding} (byte order mark)"]
  }
  let detector = @mbchardet.Detector::new(
    allow_iso_2022_jp=settings.allow_iso_2022_jp,
  )
  let non_ascii = detector.feed(data[:], last=true)
  let guess = detector.guess(tld?=settings.tld, allow_utf8=settings.allow_utf8)
  let note = if data.length() == 0 {
    " (empty)"
  } else if !non_ascii && guess != Iso2022Jp {
    // Every encoding guessed then reads ASCII the same way.
    " (ASCII only)"
  } else {
    ""
  }
  let lines = ["\{path}: \{guess}\{note}"]
  if settings.scores {
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
