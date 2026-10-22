//! Writes the golden test data: golden_data_test.mbt, the scores chardetng
//! 1.0.0 gives the test inputs, and golden_trace_wbtest.mbt, how the GBK,
//! Big5, Shift_JIS, EUC-JP and ISO-2022-JP decoders of encoding_rs answer
//! byte by byte.
//!
//!     cargo run --release --manifest-path tools/golden/Cargo.toml -- \
//!         tools/corpus.tsv golden_data_test.mbt golden_trace_wbtest.mbt
//!
//! The inputs are every row of tools/corpus.tsv encoded in each encoding
//! mbchardet scores that can represent it without loss, followed by
//! hand-written edge cases, without duplicates. Each input is fed in several
//! ways: whole with the end of the stream marked, whole without it, and in
//! chunks of 1, 2, 3 and 7 bytes. For each way the file records chardetng's
//! find_score for every encoding mbchardet scores so far; chunked results are
//! written only where they differ from the whole input.
//!
//! The traces feed byte sequences to a new decoder one byte per call, as
//! chardetng's candidates do, and hash every answer: the code units written
//! and whether and how long a sequence was malformed. The sequence sets are
//! described in `traces` and repeated in cjk_decoder_wbtest.mbt and
//! japanese_decoder_wbtest.mbt.

use chardetng::{EncodingDetector, Iso2022JpDetection};
use encoding_rs::*;
use std::fmt::Write as _;
use std::fs;

const ENCODINGS: [&Encoding; 25] = [
    UTF_8,
    GBK,
    BIG5,
    SHIFT_JIS,
    EUC_JP,
    ISO_2022_JP,
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
    cases.extend([
        ("GBK euro sign", b"\x80 100".to_vec()),
        ("GB18030 four-byte BMP", b"\x81\x30\x81\x30 \x84\x31\xA4\x39".to_vec()),
        ("GB18030 pointer 7457", b"\x81\x35\xF4\x37".to_vec()),
        ("GB18030 four-byte astral", b"\x90\x30\x81\x30 \xE3\x32\x9A\x35".to_vec()),
        ("GB18030 pointer out of range", b"\x84\x31\xA5\x30".to_vec()),
        ("GB18030 pointer out of range after FE", b"\xFE\x39\xFE\x39 x".to_vec()),
        ("GB18030 bad third byte", b"\x81\x30\x7F".to_vec()),
        ("GB18030 FF as third byte", b"\x81\x30\xFF ok".to_vec()),
        ("GB18030 FF as fourth byte", b"\x81\x30\xFE\xFF ok".to_vec()),
        ("GBK Mac single bytes", b"\xA0a \xFD1 \xFE\xFF x\xFFy".to_vec()),
        ("GBK PUA", b"\xAA\xA1\xAA\xA2".to_vec()),
        ("GB18030-2022 vertical forms", b"\xA6\xD9\xA6\xDA".to_vec()),
        ("GBK truncated", b"\xC4\xE3\xC4".to_vec()),
        ("Big5 special pointers", b"\x88\x62\x88\x64\x88\xA3\x88\xA5".to_vec()),
        ("Big5 unmapped pairs", b"\x81\x40\x81\xA1 x\x81\x7E".to_vec()),
        ("Big5 Mac single bytes", b"\xA0a\xFD \xFE\xFF".to_vec()),
        ("lone FF and 80", b"\xFFa\x80".to_vec()),
        ("Big5 lead then space", b"\xA4 \xA4\x40".to_vec()),
        ("Big5 truncated", b"\xA7\x41\xA7".to_vec()),
        (
            "half-width katakana",
            b"\xB6\xDE\xC0\xB6\xC5 \xCA\xDF\xB0\xC3\xA8 \xB1\xDE".to_vec(),
        ),
        // Voicing marks after the first and last katakana that take them, and
        // after the ones next to those that do not.
        (
            "half-width voicing marks",
            b"\xB3\xDE \xB2\xDE \xC4\xDE \xC5\xDE \xCA\xDF \xC9\xDF \xCE\xDF \xCF\xDF".to_vec(),
        ),
        ("EUC-JP half-width katakana", b"\x8E\xB6\x8E\xDE\x8E\xCA\x8E\xDF".to_vec()),
        (
            "EUC-JP half-width voicing marks",
            b"\x8E\xB3\x8E\xDE \x8E\xC5\x8E\xDE \x8E\xCF\x8E\xDF".to_vec(),
        ),
        ("Shift_JIS 0x80", b"x\x80y".to_vec()),
        ("Shift_JIS user-defined", b"\xF0\x40\xF9\xFC".to_vec()),
        ("Shift_JIS extensions", b"\x85\x40\x88\x40 \xFD\xA0".to_vec()),
        ("Shift_JIS excluded pair", b"\x82\xFA".to_vec()),
        ("Shift_JIS truncated", b"\x82\xA0\x82".to_vec()),
        ("JIS X 0212", b"\x8F\xB0\xA1\x8F\xA2\xAF".to_vec()),
        ("EUC-JP extension pair", b"\xA9\xA1 x".to_vec()),
        ("EUC-JP excluded pair", b"\xAD\xD8".to_vec()),
        ("EUC-JP truncated", b"\xA4\xA2\xA4".to_vec()),
        ("ISO-2022-JP", b"\x1B$B$3$s\x1B(B abc".to_vec()),
        ("ISO-2022-JP Roman and katakana", b"\x1B(J\\~\x1B(I12\x1B(B".to_vec()),
        ("ISO-2022-JP consecutive escapes", b"\x1B$B\x1B(B".to_vec()),
        ("ISO-2022-JP bad escape", b"\x1B(Z".to_vec()),
        ("ISO-2022-JP ESC at the end", b"abc\x1B".to_vec()),
        ("ISO-2022-JP shift out", b"\x1B(Ba\x0Eb".to_vec()),
    ]);
    // A Big5 pair that decodes outside the BMP: the first in pointer order.
    let mut astral = None;
    'search: for lead in 0x81u8..=0xFE {
        for trail in (0x40u8..=0x7E).chain(0xA1..=0xFE) {
            let pair = [lead, trail];
            let (text, malformed) = BIG5.decode_without_bom_handling(&pair);
            if !malformed && text.chars().any(|c| c as u32 > 0xFFFF) {
                astral = Some(vec![lead, trail, b' ', lead, trail]);
                break 'search;
            }
        }
    }
    cases.push(("Big5 outside the BMP", astral.expect("Big5 has astral pairs")));
    let mut owned: Vec<(String, Vec<u8>)> = cases
        .into_iter()
        .map(|(label, bytes)| (label.to_string(), bytes))
        .collect();
    // Pairs on both sides of the edges of the ranges chardetng treats as
    // extensions or excludes from them, one input each.
    let shift_jis_pairs = [
        [0x82, 0xF9], [0x82, 0xFA], [0x84, 0xDC], [0x84, 0xDD], [0x84, 0xE4], [0x84, 0xE5],
        [0x84, 0xFA], [0x84, 0xFB], [0x86, 0xF1], [0x86, 0xF2], [0x86, 0xFA], [0x86, 0xFB],
        [0x87, 0x76], [0x87, 0x77], [0x87, 0x7D], [0x87, 0x7E], [0xFC, 0xF4], [0xFC, 0xF5],
    ];
    let euc_jp_pairs = [
        [0xA8, 0xDE], [0xA8, 0xDF], [0xA8, 0xE6], [0xA8, 0xE7], [0xAC, 0xF3], [0xAC, 0xF4],
        [0xAC, 0xFC], [0xAC, 0xFD], [0xAD, 0xD7], [0xAD, 0xD8], [0xAD, 0xDE], [0xAD, 0xDF],
    ];
    for (encoding, pairs) in [("Shift_JIS", &shift_jis_pairs[..]), ("EUC-JP", &euc_jp_pairs[..])] {
        for pair in pairs {
            let label = format!("{} pair {:02X} {:02X}", encoding, pair[0], pair[1]);
            owned.push((label, vec![b'x', pair[0], pair[1], b' ']));
        }
    }
    for (row, last) in [(0xA2, 0xA1), (0xA3, 0xA1), (0xED, 0xFE), (0xFE, 0xF6), (0xFE, 0xF7)] {
        let label = format!("EUC-JP JIS X 0212 pair {:02X} {:02X}", row, last);
        owned.push((label, vec![b'x', 0x8F, row, last, b' ']));
    }
    for (label, text, encoding) in [
        ("all-caps Russian", "ПРИВЕТ, МИР. ЭТО ТЕСТ.", KOI8_U),
        ("all-caps Russian", "ПРИВЕТ, МИР. ЭТО ТЕСТ.", WINDOWS_1251),
        ("mixed-case Greek", "ΚαΛηΜέΡα κόσμε", WINDOWS_1253),
        ("Greek next to Latin", "Αθήνα Athens Θεσσαλονίκη", ISO_8859_7),
        ("Arabic and French", "مرحبا Bonjour à tous مع السلامة", WINDOWS_1256),
        ("UTF-8 with BOM", "\u{FEFF}Grüße", UTF_8),
        ("truncated UTF-8", "Grüß", UTF_8),
        ("pinyin and Hanzi", "Zhōngwén 中文", GBK),
        ("Russian", "Привет, мир", GBK),
        ("Russian", "Привет, мир", BIG5),
        ("Hanzi next to Latin", "用UTF-8編碼的文字", BIG5),
        ("Kanji next to Latin", "UTF-8で書かれた文書", SHIFT_JIS),
        ("wi and we", "ゐゑヰヱ", EUC_JP),
        ("wi and we", "ゐゑヰヱ", SHIFT_JIS),
        ("Russian", "Привет, мир", SHIFT_JIS),
    ] {
        let mut bytes = encode(text, encoding).expect("edge case must be encodable");
        if label == "truncated UTF-8" {
            bytes.pop();
        }
        owned.push((format!("{} in {}", label, encoding.name()), bytes));
    }
    owned
}

/// FNV-1a over 32-bit words, each as four little-endian bytes.
struct Fnv(u64);

impl Fnv {
    fn new() -> Self {
        Fnv(0xcbf2_9ce4_8422_2325)
    }

    fn word(&mut self, word: u32) {
        for b in word.to_le_bytes() {
            self.0 ^= u64::from(b);
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }
}

/// Feeds `sequence` to a new decoder one byte per call and hashes each
/// answer: [0, written, units...] when the byte was consumed, [1, length,
/// written, units...] for a malformed sequence. GBK and ISO-2022-JP stop at
/// the first malformed sequence, because chardetng's candidates then reset
/// the decoder or give up; Big5, Shift_JIS and EUC-JP go on, as their
/// candidates do. Then the end of the stream: [2, 1] if it is malformed,
/// else [2, 0].
fn trace(encoding: &'static Encoding, sequence: &[u8], hash: &mut Fnv) {
    let mut decoder = encoding.new_decoder_without_bom_handling();
    let mut dst = [0u16; 2];
    for &b in sequence {
        let (result, _, written) = decoder.decode_to_utf16_without_replacement(&[b], &mut dst, false);
        match result {
            DecoderResult::InputEmpty => {
                hash.word(0);
                hash.word(written as u32);
            }
            DecoderResult::Malformed(length, _) => {
                hash.word(1);
                hash.word(u32::from(length));
                hash.word(written as u32);
            }
            DecoderResult::OutputFull => unreachable!(),
        }
        for &u in &dst[..written] {
            hash.word(u32::from(u));
        }
        if (encoding == GBK || encoding == ISO_2022_JP)
            && matches!(result, DecoderResult::Malformed(..))
        {
            return;
        }
    }
    let (result, _, written) = decoder.decode_to_utf16_without_replacement(b"", &mut dst, true);
    assert_eq!(written, 0);
    hash.word(2);
    hash.word(matches!(result, DecoderResult::Malformed(..)) as u32);
}

fn hash_of(encoding: &'static Encoding, sequences: impl Iterator<Item = Vec<u8>>) -> u64 {
    let mut hash = Fnv::new();
    for sequence in sequences {
        trace(encoding, &sequence, &mut hash);
    }
    hash.0
}

/// The GB18030 four-byte sequences for one first byte: every second byte
/// 0x30 to 0x39, then third and fourth bytes from the lists below; the first
/// bytes 0x81 to 0x84 cover every BMP pointer.
fn gb18030_four_byte(first: u8) -> Vec<Vec<u8>> {
    let all = first <= 0x84;
    let thirds: Vec<u8> = if all {
        (0x81..=0xFE).chain([0x00, 0x30, 0x7F, 0x80, 0xFF]).collect()
    } else {
        vec![0x81, 0x82, 0xA0, 0xA1, 0xFD, 0xFE, 0x30, 0x80, 0xFF]
    };
    let fourths: Vec<u8> = if all {
        (0x30..=0x39).chain([0x2F, 0x3A, 0x80, 0xFF]).collect()
    } else {
        vec![0x30, 0x35, 0x39, 0x2F, 0x3A, 0xFF]
    };
    let mut sequences = Vec::new();
    for second in 0x30..=0x39 {
        for &third in &thirds {
            if (0x81..=0xFE).contains(&third) {
                for &fourth in &fourths {
                    sequences.push(vec![first, second, third, fourth]);
                }
            } else {
                sequences.push(vec![first, second, third]);
            }
        }
    }
    sequences
}

/// After an error or a character: each lead, a second byte from the list,
/// then two more bytes.
fn after(lead: u8) -> Vec<Vec<u8>> {
    let mut sequences = Vec::new();
    for second in [0x00, 0x30, 0x7F, 0x80, 0xA0, 0xFF, 0x40, 0xA1] {
        for next in [0x41, 0x81, 0xA4, 0xFF] {
            sequences.push(vec![lead, second, next, 0x40]);
        }
    }
    sequences
}

/// EUC-JP JIS X 0212: 0x8F, a lead, then every byte.
fn jis0212(lead: u8) -> Vec<Vec<u8>> {
    (0u8..=255).map(|t| vec![0x8F, lead, t]).collect()
}

/// The ISO-2022-JP escape sequences that select ASCII, Roman, katakana and
/// JIS X 0208 (two of them).
const DESIGNATIONS: [[u8; 3]; 5] = [
    [0x1B, 0x28, 0x42],
    [0x1B, 0x28, 0x4A],
    [0x1B, 0x28, 0x49],
    [0x1B, 0x24, 0x40],
    [0x1B, 0x24, 0x42],
];

/// ESC followed by every byte, and ESC ( and ESC $ followed by every byte.
fn iso_2022_jp_escapes() -> Vec<Vec<u8>> {
    let mut sequences = Vec::new();
    for x in 0u8..=255 {
        sequences.push(vec![0x1B, x]);
        sequences.push(vec![0x1B, 0x28, x]);
        sequences.push(vec![0x1B, 0x24, x]);
    }
    sequences
}

/// A designation followed by every byte.
fn iso_2022_jp_after(designation: [u8; 3]) -> Vec<Vec<u8>> {
    (0u8..=255).map(|b| [&designation[..], &[b]].concat()).collect()
}

/// JIS X 0208 selected, a lead, then every byte.
fn iso_2022_jp_jis0208(lead: u8) -> Vec<Vec<u8>> {
    (0u8..=255).map(|t| vec![0x1B, 0x24, 0x42, lead, t]).collect()
}

/// Pairs of designations with nothing, a letter, a JIS X 0208 pair or a
/// lone lead between them, then inputs that end inside a sequence.
fn iso_2022_jp_sequences() -> Vec<Vec<u8>> {
    let mut sequences = Vec::new();
    for first in DESIGNATIONS {
        for second in DESIGNATIONS {
            for between in [&b""[..], b"\x41", b"\x21\x21", b"\x21"] {
                sequences.push([&first[..], between, &second[..]].concat());
            }
        }
    }
    for tail in [
        &b"\x1B"[..],
        b"\x1B\x28",
        b"\x1B\x24",
        b"\x1B\x24\x42\x30",
        b"\x41\x1B",
        b"\x1B\x28\x42\x41",
    ] {
        sequences.push(tail.to_vec());
    }
    sequences
}

fn hashes(encoding: &'static Encoding, groups: impl Iterator<Item = Vec<Vec<u8>>>) -> String {
    groups
        .map(|group| format!("{}UL", hash_of(encoding, group.into_iter())))
        .collect::<Vec<_>>()
        .join(", ")
}

fn traces() -> String {
    let mut out = String::new();
    out.push_str("// Generated by tools/golden from encoding_rs 0.8.42. Do not edit.\n");
    out.push_str("// FNV-1a hashes of how its CJK decoders answer the byte sequences\n");
    out.push_str("// that cjk_decoder_wbtest.mbt and japanese_decoder_wbtest.mbt describe.\n");
    let leads = || 0x81u8..=0xFE;
    for (name, encoding) in [
        ("gbk", GBK),
        ("big5", BIG5),
        ("shift_jis", SHIFT_JIS),
        ("euc_jp", EUC_JP),
    ] {
        let single = hash_of(encoding, (0u8..=255).map(|b| vec![b]));
        write!(out, "\n///|\nlet golden_{}_single : UInt64 = {}UL\n", name, single).unwrap();
        let pairs: Vec<String> = leads()
            .map(|lead| format!("{}UL", hash_of(encoding, (0u8..=255).map(move |b| vec![lead, b]))))
            .collect();
        write!(out, "\n///|\nlet golden_{}_pairs : FixedArray[UInt64] = [{}]\n", name, pairs.join(", ")).unwrap();
    }
    let four: Vec<String> = leads()
        .map(|first| format!("{}UL", hash_of(GBK, gb18030_four_byte(first).into_iter())))
        .collect();
    write!(out, "\n///|\nlet golden_gbk_four_byte : FixedArray[UInt64] = [{}]\n", four.join(", ")).unwrap();
    for (name, encoding) in [("big5", BIG5), ("shift_jis", SHIFT_JIS), ("euc_jp", EUC_JP)] {
        let after = hashes(encoding, leads().map(after));
        write!(out, "\n///|\nlet golden_{}_after : FixedArray[UInt64] = [{}]\n", name, after).unwrap();
    }
    let jis0212_hashes = hashes(EUC_JP, (0xA1u8..=0xFE).map(jis0212));
    write!(out, "\n///|\nlet golden_euc_jp_jis0212 : FixedArray[UInt64] = [{}]\n", jis0212_hashes).unwrap();
    let single = hash_of(ISO_2022_JP, (0u8..=255).map(|b| vec![b]));
    write!(out, "\n///|\nlet golden_iso_2022_jp_single : UInt64 = {}UL\n", single).unwrap();
    let escapes = hash_of(ISO_2022_JP, iso_2022_jp_escapes().into_iter());
    write!(out, "\n///|\nlet golden_iso_2022_jp_escapes : UInt64 = {}UL\n", escapes).unwrap();
    let designations = hashes(ISO_2022_JP, DESIGNATIONS.into_iter().map(iso_2022_jp_after));
    write!(out, "\n///|\nlet golden_iso_2022_jp_designations : FixedArray[UInt64] = [{}]\n", designations).unwrap();
    let jis0208_hashes = hashes(ISO_2022_JP, (0x21u8..=0x7E).map(iso_2022_jp_jis0208));
    write!(out, "\n///|\nlet golden_iso_2022_jp_jis0208 : FixedArray[UInt64] = [{}]\n", jis0208_hashes).unwrap();
    let sequences = hash_of(ISO_2022_JP, iso_2022_jp_sequences().into_iter());
    write!(out, "\n///|\nlet golden_iso_2022_jp_sequences : UInt64 = {}UL\n", sequences).unwrap();
    out
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: mbchardet-golden CORPUS_TSV SCORES_MBT TRACES_MBT");
        std::process::exit(2);
    }
    fs::write(&args[3], traces()).expect("cannot write the traces");
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
