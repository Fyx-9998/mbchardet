//! Writes chardetng_tests_data_test.mbt from the unit tests of chardetng
//! 1.0.0, read from its src/lib.rs.
//!
//! Most of those tests are one call of `check(text, ENCODING)`, which encodes
//! the text with encoding_rs, splitting off Vietnamese tones with detone
//! first for windows-1258, and expects a detector that allows ISO-2022-JP
//! and is fed the bytes whole to guess that encoding without a top-level
//! domain and with UTF-8 denied. For each of them the file records the
//! name, the encoding, the bytes as `check` makes them and their text as
//! encoding_rs decodes them: the test's text, with numeric character
//! references where the encoding lacks a character, as in test_fa. The
//! names of the other tests, which build their bytes or feed them in
//! chunks, are listed for chardetng_tests_test.mbt, which ports them by
//! hand.
//!
//! Before writing, the tool runs chardetng on each input as `check` does,
//! so the file only holds what chardetng 1.0.0 itself passes.

use super::{bytes_literal, string_literal, ALL};
use chardetng::{EncodingDetector, Iso2022JpDetection, Utf8Detection};
use detone::IterDecomposeVietnamese;
use encoding_rs::{Encoding, WINDOWS_1258};
use std::fmt::Write as _;
use std::fs;

/// A test of chardetng's test module.
struct Test {
    name: String,
    /// The text and the constant naming the encoding if the test is one
    /// call of `check`.
    check: Option<(String, String)>,
}

/// The value of the Rust string literal at the start of `s`, and the rest
/// of `s` after it.
fn string_value(s: &str) -> Option<(String, &str)> {
    let mut chars = s.strip_prefix('"')?.char_indices();
    let mut value = String::new();
    while let Some((i, c)) = chars.next() {
        match c {
            '"' => return Some((value, &s[i + 2..])),
            '\\' => match chars.next()?.1 {
                'n' => value.push('\n'),
                'r' => value.push('\r'),
                't' => value.push('\t'),
                '0' => value.push('\0'),
                '\\' => value.push('\\'),
                '"' => value.push('"'),
                '\'' => value.push('\''),
                'x' => {
                    let hex: String = (0..2).filter_map(|_| chars.next().map(|(_, c)| c)).collect();
                    let code = u8::from_str_radix(&hex, 16).ok()?;
                    if code > 0x7F {
                        return None;
                    }
                    value.push(code as char);
                }
                'u' => {
                    if chars.next()?.1 != '{' {
                        return None;
                    }
                    let mut hex = String::new();
                    loop {
                        match chars.next()?.1 {
                            '}' => break,
                            '_' => {}
                            c => hex.push(c),
                        }
                    }
                    value.push(char::from_u32(u32::from_str_radix(&hex, 16).ok()?)?);
                }
                _ => return None,
            },
            _ => value.push(c),
        }
    }
    None
}

/// The text and the encoding constant if `body` is exactly one call
/// `check("...", CONSTANT);`.
fn check_call(body: &str) -> Option<(String, String)> {
    let rest = body.strip_prefix("check(")?.trim_start();
    let (text, rest) = string_value(rest)?;
    let rest = rest.trim_start().strip_prefix(',')?.trim_start();
    let end = rest
        .find(|c: char| !(c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_'))
        .unwrap_or(rest.len());
    let (constant, rest) = rest.split_at(end);
    let rest = rest.trim_start();
    let rest = rest.strip_prefix(',').unwrap_or(rest).trim_start();
    if constant.is_empty() || rest.strip_prefix(')')?.trim_start() != ";" {
        return None;
    }
    Some((text, constant.to_string()))
}

/// The tests of chardetng's test module in `lib_rs`, in order, without the
/// lines that are comments.
fn tests(lib_rs: &str) -> Vec<Test> {
    let module = &lib_rs[lib_rs.find("\nmod tests {").expect("no test module")..];
    let lines: Vec<&str> = module
        .lines()
        .filter(|line| !line.trim_start().starts_with("//"))
        .collect();
    let mut tests = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        if lines[i].trim() != "#[test]" {
            i += 1;
            continue;
        }
        let signature = lines[i + 1].trim();
        let name = signature
            .strip_prefix("fn ")
            .and_then(|s| s.strip_suffix("() {"))
            .unwrap_or_else(|| panic!("unexpected test signature: {}", signature));
        let mut body = Vec::new();
        i += 2;
        while lines[i] != "    }" {
            body.push(lines[i].trim());
            i += 1;
        }
        tests.push(Test {
            name: name.to_string(),
            check: check_call(&body.join("\n")),
        });
    }
    tests
}

/// The encoding_rs encoding a constant such as `WINDOWS_1252` names.
fn named(constant: &str) -> &'static Encoding {
    ALL.iter()
        .copied()
        .find(|e| e.name().to_ascii_uppercase().replace('-', "_") == constant)
        .unwrap_or_else(|| panic!("no encoding is named {}", constant))
}

pub fn data(lib_rs_path: &str) -> String {
    let lib_rs = fs::read_to_string(lib_rs_path).expect("cannot read chardetng's src/lib.rs");
    let tests = tests(&lib_rs);
    let mut out = String::new();
    out.push_str("// Generated by tools/golden from the tests in src/lib.rs of chardetng 1.0.0,\n");
    out.push_str("// with encoding_rs 0.8.42 and detone 1.0.0. Do not edit. chardetng is\n");
    out.push_str("// licensed under the Apache License 2.0 or the MIT License, see NOTICE.\n\n");
    out.push_str("///|\n/// chardetng's tests that are one call of `check`, in the order of\n");
    out.push_str("/// src/lib.rs: (name, the encoding the test expects, the text of the bytes,\n");
    out.push_str("/// the test's text in that encoding as `check` encodes it). The text of the\n");
    out.push_str("/// bytes has the tones split off for windows-1258, as `check` splits them,\n");
    out.push_str("/// and a numeric character reference for each character the encoding\n");
    out.push_str("/// lacks, which the encoder writes instead, as in test_fa.\n");
    out.push_str("let chardetng_checks : Array[(String, String, String, Bytes)] = [\n");
    let mut others = Vec::new();
    for test in &tests {
        let Some((text, constant)) = &test.check else {
            others.push(test.name.as_str());
            continue;
        };
        let encoding = named(constant);
        let text = if encoding == WINDOWS_1258 {
            text.chars().decompose_vietnamese_tones(true).collect::<String>()
        } else {
            text.clone()
        };
        // Like `check`, keep what the encoder writes for characters the
        // encoding lacks: a numeric character reference.
        let (bytes, used, unmappable) = encoding.encode(&text);
        assert_eq!(used, encoding, "{}: encoded in another encoding", test.name);
        if unmappable {
            eprintln!("{}: not every character is in {}", test.name, encoding.name());
        }
        let decoded = encoding
            .decode_without_bom_handling_and_without_replacement(&bytes)
            .expect("encoded text decodes");
        let mut detector = EncodingDetector::new(Iso2022JpDetection::Allow);
        detector.feed(&bytes, true);
        let guess = detector.guess(None, Utf8Detection::Deny);
        assert_eq!(guess, encoding, "chardetng fails its own test {}", test.name);
        writeln!(
            out,
            "  (\"{}\", \"{}\", {}, {}),",
            test.name,
            encoding.name(),
            string_literal(&decoded),
            bytes_literal(&bytes)
        )
        .unwrap();
    }
    out.push_str("]\n\n");
    out.push_str("///|\n/// The names of chardetng's other tests, in the order of src/lib.rs.\n");
    out.push_str("let chardetng_other_tests : Array[String] = [\n");
    for name in others {
        writeln!(out, "  \"{}\",", name).unwrap();
    }
    out.push_str("]\n");
    out
}
