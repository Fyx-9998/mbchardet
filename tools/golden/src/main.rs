//! Writes golden_data_test.mbt: the scores chardetng 1.0.0 gives the test
//! inputs, for mbchardet's golden test to compare against.
//!
//!     cargo run --release --manifest-path tools/golden/Cargo.toml -- \
//!         tools/corpus.tsv golden_data_test.mbt
//!
//! The inputs are every row of tools/corpus.tsv encoded in UTF-8 and in each
//! single-byte encoding that can represent it without loss, followed by
//! hand-written edge cases, without duplicates. Each input is fed in several
//! ways: whole with
//! the end of the stream marked, whole without it, and in chunks of 1, 2, 3
//! and 7 bytes. For each way the file records chardetng's find_score for
//! every encoding mbchardet scores so far; chunked results are written only
//! where they differ from the whole input.

use chardetng::{EncodingDetector, Iso2022JpDetection};
use encoding_rs::*;
use std::fmt::Write as _;
use std::fs;

const ENCODINGS: [&Encoding; 20] = [
    UTF_8,
    WINDOWS_874,
    WINDOWS_1250,
    WINDOWS_1251,
    WINDOWS_1252,
    WINDOWS_1253,
    WINDOWS_1254,
    WINDOWS_1255,
    WINDOWS_1256,
    WINDOWS_1257,
    WINDOWS_1258,
    ISO_8859_2,
    ISO_8859_4,
    ISO_8859_5,
    ISO_8859_6,
    ISO_8859_7,
    ISO_8859_8,
    ISO_8859_13,
    KOI8_U,
    IBM866,
];

const CHUNK_SIZES: [usize; 4] = [1, 2, 3, 7];

fn scores(input: &[u8], chunk: Option<usize>, last: bool) -> String {
    let mut detector = EncodingDetector::new(Iso2022JpDetection::Allow);
    match chunk {
        None => {
            detector.feed(input, last);
        }
        Some(size) => {
            let mut chunks: Vec<&[u8]> = input.chunks(size).collect();
            let final_chunk = chunks.pop().unwrap_or(b"");
            for c in chunks {
                detector.feed(c, false);
            }
            detector.feed(final_chunk, last);
        }
    }
    let values: Vec<String> = ENCODINGS
        .iter()
        .map(|e| match detector.find_score(e) {
            Some(score) => score.to_string(),
            None => "-".to_string(),
        })
        .collect();
    values.join(" ")
}

fn bytes_literal(bytes: &[u8]) -> String {
    let mut out = String::from("b\"");
    for &b in bytes {
        if (0x20..0x7F).contains(&b) && b != b'"' && b != b'\\' {
            out.push(b as char);
        } else {
            write!(out, "\\x{:02X}", b).unwrap();
        }
    }
    out.push('"');
    out
}

fn encode(text: &str, encoding: &'static Encoding) -> Option<Vec<u8>> {
    let (bytes, used, unmappable) = encoding.encode(text);
    if unmappable || used != encoding {
        None
    } else {
        Some(bytes.into_owned())
    }
}

/// Hand-written inputs for paths the corpus may not reach.
fn edge_cases() -> Vec<(String, Vec<u8>)> {
    let mut cases: Vec<(&str, Vec<u8>)> = vec![
        ("empty", b"".to_vec()),
        ("ASCII only", b"Plain ASCII, nothing else.".to_vec()),
        ("ESC and ASCII", b"\x1B$B\x1B(B text".to_vec()),
        ("ESC, then non-ASCII", b"ab\x1B(Bcd caf\xE9".to_vec()),
        ("non-ASCII first", b"\xE9t\xE9".to_vec()),
        ("non-ASCII at 1", b"a\xE9t\xE9".to_vec()),
        ("non-ASCII at 2", b"ab\xE9t\xE9".to_vec()),
        ("non-ASCII at 3", b"abc\xE9t\xE9".to_vec()),
        ("C1 controls", b"x \x80\x81\x8D\x8F\x90\x9D y".to_vec()),
        ("bytes FD to FF", b"\xFD\xFE\xFF".to_vec()),
        ("run of five non-ASCII letters", b"x \xE9\xE8\xEA\xEB\xE0 y".to_vec()),
        (
            "Spanish ordinals",
            b"el n.\xBA 5 y la 3\xAA vez, N\xBA 1 y n\xBA2, M\xAA D\xAA S\xAA, \xA9 2026 ".to_vec(),
        ),
        ("Italian ordinals", b" X\xBA secolo, II\xAA guerra, 3\xBA posto ".to_vec()),
        // The first non-ASCII byte comes two bytes after n, which decides
        // whether a digit after it gets the ordinal bonus.
        ("n.\u{BA} and a digit first", b"n.\xBA1 y n.\xBA2".to_vec()),
        ("n.\u{BA} and a digit later", b"Calle Mayor, n.\xBA12".to_vec()),
        ("English I and right quote", b"I\x92m sure I\x92ll go.".to_vec()),
        (
            "IBM866 with A0",
            b"\xA0\xA0 \xA0\x8F\xE0\xA8\xA2\xA5\xE2 \xAC\xA8\xE0\xA0".to_vec(),
        ),
    ];
    let mut long_prefix = vec![b'a'; 100];
    long_prefix.extend_from_slice(b" caf\xE9 cr\xE8me");
    cases.push(("long ASCII prefix", long_prefix));
    let mut owned: Vec<(String, Vec<u8>)> = cases
        .into_iter()
        .map(|(label, bytes)| (label.to_string(), bytes))
        .collect();
    for (label, text, encoding) in [
        ("all-caps Russian", "ПРИВЕТ, МИР. ЭТО ТЕСТ.", KOI8_U),
        ("all-caps Russian", "ПРИВЕТ, МИР. ЭТО ТЕСТ.", WINDOWS_1251),
        ("mixed-case Greek", "ΚαΛηΜέΡα κόσμε", WINDOWS_1253),
        ("Greek next to Latin", "Αθήνα Athens Θεσσαλονίκη", ISO_8859_7),
        ("Arabic and French", "مرحبا Bonjour à tous مع السلامة", WINDOWS_1256),
        ("UTF-8 with BOM", "\u{FEFF}Grüße", UTF_8),
        ("truncated UTF-8", "Grüß", UTF_8),
    ] {
        let mut bytes = encode(text, encoding).expect("edge case must be encodable");
        if label == "truncated UTF-8" {
            bytes.pop();
        }
        owned.push((format!("{} in {}", label, encoding.name()), bytes));
    }
    owned
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: mbchardet-golden CORPUS_TSV OUTPUT_MBT");
        std::process::exit(2);
    }
    let corpus = fs::read_to_string(&args[1]).expect("cannot read the corpus");
    let mut inputs: Vec<(String, Vec<u8>)> = Vec::new();
    for line in corpus.lines() {
        if line.starts_with('#') || line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 3, "corpus line without three fields: {}", line);
        for &encoding in ENCODINGS.iter() {
            if let Some(bytes) = encode(fields[2], encoding) {
                let label = format!("{} {} in {}", fields[0], fields[1], encoding.name());
                inputs.push((label, bytes));
            }
        }
    }
    inputs.extend(edge_cases());
    // Text without letters outside ASCII encodes to the same bytes in many
    // encodings; keep the first of identical inputs.
    let mut seen = std::collections::HashSet::new();
    inputs.retain(|(_, bytes)| seen.insert(bytes.clone()));

    let mut out = String::new();
    out.push_str("// Generated by tools/golden from chardetng 1.0.0. Do not edit.\n");
    out.push_str("// Corpus inputs are sentences from Tatoeba (https://tatoeba.org),\n");
    out.push_str("// CC BY 2.0 FR, encoded; the label names their Tatoeba ids. See NOTICE.\n\n");
    out.push_str("///|\n/// The encodings each score string lists, in order.\n");
    out.push_str("let golden_encodings : Array[String] = [\n");
    for e in ENCODINGS.iter() {
        writeln!(out, "  \"{}\",", e.name()).unwrap();
    }
    out.push_str("]\n\n");
    out.push_str("///|\n/// (label, input, scores at the end of the stream, scores without the\n");
    out.push_str("/// end marked, [(chunk size, scores at the end)] where those differ).\n");
    out.push_str(
        "let golden_cases : Array[(String, Bytes, String, String, Array[(Int, String)])] = [\n",
    );
    for (label, bytes) in &inputs {
        let whole = scores(bytes, None, true);
        let open = scores(bytes, None, false);
        let mut chunked = Vec::new();
        for &size in CHUNK_SIZES.iter() {
            let s = scores(bytes, Some(size), true);
            if s != whole {
                chunked.push(format!("({}, \"{}\")", size, s));
            }
        }
        writeln!(
            out,
            "  (\"{}\", {}, \"{}\", \"{}\", [{}]),",
            label,
            bytes_literal(bytes),
            whole,
            open,
            chunked.join(", ")
        )
        .unwrap();
    }
    out.push_str("]\n");
    fs::write(&args[2], out).expect("cannot write the output");
    eprintln!("{} inputs", inputs.len());
}
