///|
fn examine(
  data : Bytes,
  mode~ : String = "text",
  charset~ : String = "",
  tld~ : String = "",
  allow_utf8~ : Bool = true,
  allow_iso_2022_jp~ : Bool = true,
) -> Json {
  @json.parse(
    @demo.examine(data, mode, charset, tld, allow_utf8, allow_iso_2022_jp),
  ) catch {
    error => abort("examine did not return JSON: \{error}")
  }
}

///|
/// "Keď som ju uvidel, zamrelo mi srdce.", Tatoeba sentence 9935594
/// (CC BY 2.0 FR), in windows-1250.
let slovak : Bytes = b"Ke\xEF som ju uvidel, zamrelo mi srdce."

///|
test "examine: the guess, its scores and the text" {
  let result = examine(slovak, tld="sk")
  guard result
    // The scores leave out the TLD hint, as for the command-line tool.
    is {
      "problem": Null,
      "encoding": "windows-1250",
      "source": "detection",
      "ascii": False,
      "scores": Array([{ "encoding": "ISO-8859-4", .. }, ..] as scores),
      "ruled_out": ["UTF-8", ..],
      "decoded": {
        "text": "Keď som ju uvidel, zamrelo mi srdce.",
        "error": Null,
        ..
      },
      ..
    } else {
    fail("unexpected result: \{result.stringify()}")
  }
  // The scores are those of the detector, without the TLD hint, highest
  // first, and equal ones in the order of Encoding::all().
  let detector = @mbchardet.Detector::new()
  detector.feed(slovak[:], last=true) |> ignore
  let names = []
  for entry in scores {
    guard entry is { "encoding": String(name), "score": Number(score, ..), .. } else {
      fail("unexpected score: \{entry.stringify()}")
    }
    guard @mbchardet.Encoding::from_label(name) is Some(encoding) else {
      fail("unknown encoding \{name}")
    }
    assert_eq(detector.score(encoding), Some(score.to_int64()))
    names.push(name)
  }
  assert_eq(names, [
    "ISO-8859-4", "windows-1257", "ISO-8859-13", "windows-1250", "ISO-8859-2", "windows-1252",
    "windows-1254", "windows-1258",
  ])
  // Without the hint, chardetng guesses ISO-8859-4, which decodes without
  // error but with the wrong letter.
  guard examine(slovak)
    is {
      "encoding": "ISO-8859-4",
      "decoded": { "text": "Keī som ju uvidel, zamrelo mi srdce.", .. },
      ..
    } else {
    fail("unexpected result without the TLD")
  }
  // The TLD is taken in any case.
  guard examine(slovak, tld="SK") is { "encoding": "windows-1250", .. } else {
    fail("SK was not taken for sk")
  }
}

///|
test "examine: a byte order mark, then the charset" {
  let data = b"\xEF\xBB\xBFname,city\n"
  guard examine(data, charset="gbk")
    is {
      "encoding": "UTF-8",
      "source": "bom",
      "decoded": { "text": "name,city\n", .. },
      ..
    } else {
    fail("the byte order mark did not decide")
  }
  guard examine(slovak, charset="windows-1250")
    is { "encoding": "windows-1250", "source": "charset", .. } else {
    fail("the charset did not decide")
  }
  guard examine(b"plain") is { "source": "detection", "ascii": True, .. } else {
    fail("ASCII input is not marked")
  }
}

///|
test "examine: input not valid in the encoding found" {
  // "张伟" in GBK, cut inside its second character.
  guard examine(b"\xD5\xC5\xCE", charset="gbk")
    is {
      "encoding": "GBK",
      "decoded": {
        "text": Null,
        "error": {
          "message": "invalid GBK: input ends inside a sequence that starts at offset 2",
          "offset": 2,
          "length": Null,
          ..
        },
        ..
      },
      ..
    } else {
    fail("the error is not reported")
  }
  guard examine(b"ok \x81 bad", charset="gbk")
    is { "decoded": { "error": { "offset": 3, "length": 1, .. }, .. }, .. } else {
    fail("the malformed sequence is not reported")
  }
}

///|
test "examine: HTML and XML" {
  let page = b"<meta charset=\"Shift_JIS\"><p>\x82\xB1\x82\xF1</p>"
  guard examine(page, mode="html")
    is {
      "encoding": "Shift_JIS",
      "source": "declared",
      "scores": [_, ..],
      "decoded": { "text": "<meta charset=\"Shift_JIS\"><p>こん</p>", .. },
      ..
    } else {
    fail("the declaration was not read")
  }
  // Plain text is not searched for a declaration. Two characters are too
  // few for the detector, which guesses windows-1252.
  guard examine(page)
    is { "encoding": "windows-1252", "source": "detection", .. } else {
    fail("a declaration was read in plain text")
  }
  // Without a declaration, the guess, with the options.
  guard examine(b"<p>" + slovak, mode="html", tld="sk")
    is { "encoding": "windows-1250", "source": "detection", .. } else {
    fail("the TLD was not taken for HTML")
  }
  let german = b"<p>Gr\xC3\xBC\xC3\x9Fe" // "Grüße" in UTF-8
  guard examine(german, mode="html", allow_utf8=false)
    is { "encoding": "windows-1252", .. } else {
    fail("UTF-8 was not denied for HTML")
  }
  let feed = b"<?xml version=\"1.0\" encoding=\"windows-1251\"?><rss>"
  guard examine(feed, mode="xml")
    is {
      "encoding": "windows-1251",
      "source": "declared",
      "scores": Null,
      "ruled_out": Null,
      ..
    } else {
    fail("the XML declaration was not read")
  }
  guard examine(feed, mode="xml", charset="koi8-r")
    is { "encoding": "KOI8-R", "source": "charset", .. } else {
    fail("the charset did not decide for XML")
  }
  guard examine(slovak, mode="xml")
    is { "encoding": "UTF-8", "source": "default", .. } else {
    fail("XML without a declaration is not UTF-8")
  }
}

///|
test "examine: the options of the detector" {
  let german = b"Gr\xC3\xBC\xC3\x9Fe" // "Grüße" in UTF-8
  guard examine(german, allow_utf8=false) is { "encoding": "windows-1252", .. } else {
    fail("UTF-8 was not denied")
  }
  let jis = b"\x1B$B$3$s$K$A$O\x1B(B" // こんにちは in ISO-2022-JP
  guard examine(jis) is { "encoding": "ISO-2022-JP", "ascii": True, .. } else {
    fail("ISO-2022-JP was not guessed")
  }
  guard examine(jis, allow_iso_2022_jp=false)
    is { "encoding": "UTF-8", "ruled_out": Array(ruled_out), .. } &&
    ruled_out.contains(Json::string("ISO-2022-JP")) else {
    fail("ISO-2022-JP was not denied")
  }
}

///|
test "examine: options that cannot be used" {
  for
    options in [
      examine(slovak, charset="bogus"),
      examine(slovak, tld="co.jp"),
      examine(slovak, tld="рф"),
    ] {
    guard options is { "problem": String(_), .. } else {
      fail("accepted: \{options.stringify()}")
    }
  }
}

///|
test "decode_as and encoding_names" {
  let decoded = @json.parse(@demo.decode_as(slovak, "windows-1250"))
  guard decoded
    is { "text": "Keď som ju uvidel, zamrelo mi srdce.", "error": Null, .. } else {
    fail("unexpected result: \{decoded.stringify()}")
  }
  let refused = @json.parse(@demo.decode_as(slovak, "UTF-8"))
  guard refused
    is {
      "text": Null,
      "error": {
        "message": "invalid UTF-8: malformed sequence of 1 byte at offset 2",
        "offset": 2,
        "length": 1,
        ..
      },
      ..
    } else {
    fail("unexpected result: \{refused.stringify()}")
  }
  guard @json.parse(@demo.decode_as(slovak, "bogus"))
    is { "text": Null, "error": Null, .. } else {
    fail("an unknown name decoded")
  }
  let names = @json.parse(@demo.encoding_names())
  guard names is Array(names) else { fail("no array") }
  assert_eq(names, @mbchardet.Encoding::all().map(e => Json::string(e.name())))
}
