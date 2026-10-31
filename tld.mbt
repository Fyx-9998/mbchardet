// How chardetng 1.0.0 lets the top-level domain steer its guess: the classes
// of src/tld.rs (CC0 1.0) and encoding_for_tld, encoding_is_native_to_tld and
// score_adjustment of src/lib.rs (Apache-2.0 OR MIT, Copyright Mozilla
// Foundation). See NOTICE. The tables are in detector_data.mbt.

///|
/// The position of each candidate in `Detector`, which is chardetng's order.
const CANDIDATE_UTF_8 : Int32 = 0

///|
const CANDIDATE_ISO_2022_JP : Int32 = 1

///|
const CANDIDATE_VISUAL : Int32 = 2

///|
const CANDIDATE_GBK : Int32 = 3

///|
const CANDIDATE_EUC_JP : Int32 = 4

///|
const CANDIDATE_EUC_KR : Int32 = 5

///|
const CANDIDATE_SHIFT_JIS : Int32 = 6

///|
const CANDIDATE_BIG5 : Int32 = 7

///|
const CANDIDATE_WESTERN : Int32 = 8

///|
const CANDIDATE_CYRILLIC_WINDOWS : Int32 = 9

///|
const CANDIDATE_CENTRAL_WINDOWS : Int32 = 10

///|
const CANDIDATE_CENTRAL_ISO : Int32 = 11

///|
const CANDIDATE_ARABIC_WINDOWS : Int32 = 12

///|
const CANDIDATE_ICELANDIC : Int32 = 13

///|
const CANDIDATE_TURKISH : Int32 = 14

///|
const CANDIDATE_THAI : Int32 = 15

///|
const CANDIDATE_LOGICAL : Int32 = 16

///|
const CANDIDATE_GREEK_WINDOWS : Int32 = 17

///|
const CANDIDATE_GREEK_ISO : Int32 = 18

///|
const CANDIDATE_BALTIC_WINDOWS : Int32 = 19

///|
const CANDIDATE_BALTIC_ISO13 : Int32 = 20

///|
const CANDIDATE_CYRILLIC_KOI : Int32 = 21

///|
const CANDIDATE_CYRILLIC_IBM : Int32 = 22

///|
const CANDIDATE_ARABIC_ISO : Int32 = 23

///|
const CANDIDATE_VIETNAMESE : Int32 = 24

///|
const CANDIDATE_BALTIC_ISO4 : Int32 = 25

///|
const CANDIDATE_CYRILLIC_ISO : Int32 = 26

///|
/// The first candidate the guess compares by score; the three before it are
/// handled apart.
const FIRST_NORMAL : Int32 = 3

///|
/// What a top-level domain says about the encodings to expect.
priv enum Tld {
  CentralWindows
  Cyrillic
  Western
  Greek
  TurkishAzeri
  Hebrew
  Arabic
  Baltic
  Vietnamese
  Thai
  Simplified
  Traditional
  Japanese
  Korean
  SimplifiedTraditional
  TraditionalSimplified
  CentralIso
  IcelandicFaroese
  WesternCyrillic
  CentralCyrillic
  WesternArabic
  Generic
  Eu
} derive(Eq)

///|
/// Whether `tld` has signs of a label not extracted correctly: a period, an
/// upper-case letter or a character outside ASCII.
fn contains_upper_case_period_or_non_ascii(tld : String) -> Bool {
  for c in tld {
    if c.to_int() >= 0x80 || c == '.' || (c >= 'A' && c <= 'Z') {
      return true
    }
  }
  false
}

///|
fn lookup_tld(table : FixedArray[(String, Tld)], key : StringView) -> Tld? {
  for entry in table {
    if entry.0.view() == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// The class of `tld`, which must be lower-case ASCII without periods.
fn classify_tld(tld : String) -> Tld {
  if tld.length() == 2 {
    lookup_tld(two_letter_tlds, tld).unwrap_or(Western)
  } else if tld.length() == 3 {
    if tld is ("edu" | "gov" | "mil") {
      Western
    } else {
      Generic
    }
  } else if tld.has_prefix("xn--") && tld.length() >= 8 {
    // Internationalized TLDs, for servers that also serve the same content
    // from a two-letter TLD, so that the guess is the same either way.
    lookup_tld(punycode_tlds, tld.view(start_offset=4)).unwrap_or(Generic)
  } else {
    Generic
  }
}

///|
/// The candidate whose encoding is the default for `tld`.
fn encoding_for_tld(tld : Tld) -> Int32 {
  match tld {
    CentralWindows | CentralCyrillic => CANDIDATE_CENTRAL_WINDOWS
    Cyrillic => CANDIDATE_CYRILLIC_WINDOWS
    Generic | Western | WesternCyrillic | WesternArabic | Eu =>
      CANDIDATE_WESTERN
    IcelandicFaroese => CANDIDATE_ICELANDIC
    Greek => CANDIDATE_GREEK_ISO
    TurkishAzeri => CANDIDATE_TURKISH
    Hebrew => CANDIDATE_LOGICAL
    Arabic => CANDIDATE_ARABIC_WINDOWS
    Baltic => CANDIDATE_BALTIC_WINDOWS
    Vietnamese => CANDIDATE_VIETNAMESE
    Thai => CANDIDATE_THAI
    Simplified | SimplifiedTraditional => CANDIDATE_GBK
    Traditional | TraditionalSimplified => CANDIDATE_BIG5
    Japanese => CANDIDATE_SHIFT_JIS
    Korean => CANDIDATE_EUC_KR
    CentralIso => CANDIDATE_CENTRAL_ISO
  }
}

///|
/// Whether the encoding of candidate `encoding` is expected under `tld`.
fn encoding_is_native_to_tld(tld : Tld, encoding : Int32) -> Bool {
  match tld {
    CentralWindows => encoding == CANDIDATE_CENTRAL_WINDOWS
    Cyrillic =>
      encoding
      is (CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_CYRILLIC_ISO)
    Western => encoding == CANDIDATE_WESTERN
    Greek => encoding is (CANDIDATE_GREEK_WINDOWS | CANDIDATE_GREEK_ISO)
    TurkishAzeri => encoding == CANDIDATE_TURKISH
    Hebrew => encoding == CANDIDATE_LOGICAL
    Arabic => encoding is (CANDIDATE_ARABIC_WINDOWS | CANDIDATE_ARABIC_ISO)
    Baltic =>
      encoding
      is (CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_BALTIC_ISO4)
    Vietnamese => encoding == CANDIDATE_VIETNAMESE
    Thai => encoding == CANDIDATE_THAI
    Simplified => encoding == CANDIDATE_GBK
    Traditional => encoding == CANDIDATE_BIG5
    Japanese => encoding is (CANDIDATE_SHIFT_JIS | CANDIDATE_EUC_JP)
    Korean => encoding == CANDIDATE_EUC_KR
    SimplifiedTraditional | TraditionalSimplified =>
      encoding is (CANDIDATE_GBK | CANDIDATE_BIG5)
    CentralIso => encoding == CANDIDATE_CENTRAL_ISO
    IcelandicFaroese => encoding == CANDIDATE_ICELANDIC
    WesternCyrillic =>
      encoding
      is (CANDIDATE_WESTERN
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_CYRILLIC_ISO)
    CentralCyrillic =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_CYRILLIC_ISO)
    WesternArabic =>
      encoding
      is (CANDIDATE_WESTERN | CANDIDATE_ARABIC_WINDOWS | CANDIDATE_ARABIC_ISO)
    Eu =>
      encoding
      is (CANDIDATE_WESTERN
      | CANDIDATE_ICELANDIC
      | CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_CYRILLIC_ISO
      | CANDIDATE_GREEK_WINDOWS
      | CANDIDATE_GREEK_ISO
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_BALTIC_ISO4)
    Generic => false
  }
}

///|
/// How much to take off the score of a candidate that is not native to
/// `tld` while one that is native is still possible. chardetng calls this
/// "the most ad hoc part of this library". Never called with Generic.
fn score_adjustment(score : Int64, encoding : Int32, tld : Tld) -> Int64 {
  if score < 1 {
    return 0
  }
  // Candidates that lose their whole score under this TLD.
  let unadjusted = match tld {
    CentralWindows | CentralIso =>
      encoding
      is (CANDIDATE_WESTERN
      | CANDIDATE_ICELANDIC
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_VIETNAMESE
      | CANDIDATE_TURKISH)
    Cyrillic =>
      encoding
      is (CANDIDATE_BIG5
      | CANDIDATE_GBK
      | CANDIDATE_EUC_JP
      | CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_GREEK_WINDOWS
      | CANDIDATE_GREEK_ISO
      | CANDIDATE_VISUAL
      | CANDIDATE_LOGICAL
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH)
    Western | WesternCyrillic | WesternArabic =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH
      | CANDIDATE_VIETNAMESE)
    Greek =>
      encoding
      is (CANDIDATE_BIG5
      | CANDIDATE_GBK
      | CANDIDATE_EUC_JP
      | CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_ISO
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_VISUAL
      | CANDIDATE_LOGICAL
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH)
    TurkishAzeri =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_VIETNAMESE
      | CANDIDATE_ICELANDIC)
    Hebrew =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_ISO
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_GREEK_WINDOWS
      | CANDIDATE_GREEK_ISO
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_VIETNAMESE
      | CANDIDATE_TURKISH)
    Arabic =>
      encoding
      is (CANDIDATE_BIG5
      | CANDIDATE_GBK
      | CANDIDATE_EUC_JP
      | CANDIDATE_EUC_KR
      | CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_ISO
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_GREEK_WINDOWS
      | CANDIDATE_GREEK_ISO
      | CANDIDATE_VISUAL
      | CANDIDATE_LOGICAL
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_VIETNAMESE
      | CANDIDATE_TURKISH)
    Baltic =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_ICELANDIC
      | CANDIDATE_TURKISH
      | CANDIDATE_VIETNAMESE)
    Vietnamese =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH
      | CANDIDATE_ICELANDIC)
    Thai =>
      encoding
      is (CANDIDATE_BIG5
      | CANDIDATE_GBK
      | CANDIDATE_EUC_JP
      | CANDIDATE_EUC_KR
      | CANDIDATE_SHIFT_JIS
      | CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_CYRILLIC_WINDOWS
      | CANDIDATE_CYRILLIC_ISO
      | CANDIDATE_CYRILLIC_KOI
      | CANDIDATE_CYRILLIC_IBM
      | CANDIDATE_GREEK_WINDOWS
      | CANDIDATE_GREEK_ISO
      | CANDIDATE_ARABIC_WINDOWS
      | CANDIDATE_ARABIC_ISO
      | CANDIDATE_VISUAL
      | CANDIDATE_LOGICAL
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH)
    // If the TLD default is valid, everything else scores zero.
    Simplified
    | Traditional
    | TraditionalSimplified
    | SimplifiedTraditional
    | Japanese
    | Korean => true
    IcelandicFaroese =>
      encoding
      is (CANDIDATE_CENTRAL_WINDOWS
      | CANDIDATE_CENTRAL_ISO
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH
      | CANDIDATE_VIETNAMESE)
    CentralCyrillic =>
      encoding
      is (CANDIDATE_BIG5
      | CANDIDATE_GBK
      | CANDIDATE_EUC_JP
      | CANDIDATE_GREEK_WINDOWS
      | CANDIDATE_GREEK_ISO
      | CANDIDATE_VISUAL
      | CANDIDATE_LOGICAL
      | CANDIDATE_BALTIC_WINDOWS
      | CANDIDATE_BALTIC_ISO4
      | CANDIDATE_BALTIC_ISO13
      | CANDIDATE_TURKISH)
    Eu =>
      encoding
      is (CANDIDATE_BIG5
      | CANDIDATE_GBK
      | CANDIDATE_EUC_JP
      | CANDIDATE_TURKISH
      | CANDIDATE_VIETNAMESE)
    Generic => abort("score_adjustment: not for a generic domain")
  }
  if unadjusted {
    score
  } else {
    score / 50 + 60
  }
}
