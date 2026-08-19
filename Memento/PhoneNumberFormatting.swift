import Foundation

// MARK: - Region metadata

/// One country's dialling rules: the trunk code people drop in when they
/// write the number the local way, and how the rest of the digits group.
struct PhoneRegion: Equatable {
    var iso: String              // ISO 3166-1 alpha-2, e.g. "GB"
    var callingCode: String      // without the "+", e.g. "44"
    var trunkPrefix: String = "" // dialled before the national number at home
    var trunkJoiner: String = "" // "" gives "07911…", " " gives "1 (415)…"
    var templates: [PhoneTemplate] = []

    /// 🇬🇧, 🇺🇸 … built from the ISO code's regional indicator symbols.
    var flag: String {
        var scalars = String.UnicodeScalarView()
        for letter in iso.uppercased().unicodeScalars {
            guard letter.value >= 65, letter.value <= 90,
                  let indicator = UnicodeScalar(0x1F1E6 + letter.value - 65) else { return "" }
            scalars.append(indicator)
        }
        return String(scalars)
    }

    var localizedName: String {
        Locale.current.localizedString(forRegionCode: iso) ?? iso
    }
}

/// A digit grouping such as `(###) ###-####`, where every `#` takes one digit
/// of the national number. `prefixes` limits it to numbers starting with those
/// digits; an empty list applies to any.
struct PhoneTemplate: Equatable {
    let pattern: String
    let prefixes: [String]

    init(_ pattern: String, prefixes: [String] = []) {
        self.pattern = pattern
        self.prefixes = prefixes
    }

    var digitCount: Int {
        pattern.reduce(0) { $1 == "#" ? $0 + 1 : $0 }
    }

    /// Matches on the digits available so far, so a half-typed number still
    /// picks the grouping it is heading towards.
    func accepts(_ nationalNumber: String) -> Bool {
        guard !prefixes.isEmpty else { return true }
        return prefixes.contains { prefix in
            let shared = min(prefix.count, nationalNumber.count)
            guard shared > 0 else { return false }
            return prefix.prefix(shared) == nationalNumber.prefix(shared)
        }
    }
}

// MARK: - Formatter

/// Presents phone numbers the way iOS Contacts does: national grouping, with
/// brackets for the countries that use them. It also names the country behind
/// an explicit `+` or `00` prefix so a flag can be shown beside it.
///
/// Apple exposes no public phone-formatting API and the app takes no
/// third-party dependencies, so the grouping rules live in `regionTable`
/// below. Countries without a hand-written rule still get their flag and a
/// readable generic grouping.
enum PhoneNumberFormatter {

    private static let digits = Set("0123456789")
    /// Punctuation a phone number may contain. Anything else (letters, "ext",
    /// a note in brackets) means the text isn't ours to reformat.
    private static let punctuation = Set(" ()-./\u{00A0}\u{2011}\u{2013}\u{2014}")

    // MARK: Public API

    /// The display form of a stored number. Text that isn't a plain phone
    /// number comes back untouched.
    static func display(_ raw: String, defaultRegion: String? = nil) -> String {
        formatted(raw, defaultRegion: defaultRegion) ?? raw.trimmed
    }

    /// The country the number points at, but only when it says so itself with
    /// a `+` or `00` prefix. A bare national number is ambiguous.
    static func region(for raw: String) -> PhoneRegion? {
        guard let parsed = parse(raw.trimmed, defaultRegion: nil),
              parsed.isInternational,
              let region = parsed.region else { return nil }
        return narrowed(region, nationalNumber: parsed.nationalNumber)
    }

    /// Reformats after a keystroke. Takes the previous text too, so deleting a
    /// bracket or space we inserted removes the digit it belonged to instead of
    /// stalling on a separator we would only put straight back.
    static func formatWhileTyping(old: String, new: String, defaultRegion: String? = nil) -> String {
        let deleting = new.count < old.count
        var candidate = new
        // Only a genuine single-separator backspace takes a digit with it:
        // exactly one character gone, and it wasn't a digit. Anything else
        // with matching digit counts must keep every digit, such as pasting
        // a number over a selected, formatted one.
        if old.count - new.count == 1, digitCount(of: new) == digitCount(of: old) {
            // The digit that owned the separator is the one just before the
            // removal point, not the number's last digit. A mid-string
            // delete must leave that one alone.
            let removalPoint = firstDivergence(old: old, new: new)
            if let owner = candidate[..<removalPoint].lastIndex(where: { digits.contains($0) }) {
                candidate.remove(at: owner)
            }
        }
        guard let result = formatted(candidate, defaultRegion: defaultRegion) else { return new }
        guard deleting else { return result }
        // Don't hand back the separator they were trying to delete.
        return String(result.reversed().drop { punctuation.contains($0) }.reversed())
    }

    /// Where `new` (which is `old` minus one character) stops matching `old`.
    private static func firstDivergence(old: String, new: String) -> String.Index {
        var oldIndex = old.startIndex
        var newIndex = new.startIndex
        while newIndex < new.endIndex, oldIndex < old.endIndex, old[oldIndex] == new[newIndex] {
            oldIndex = old.index(after: oldIndex)
            newIndex = new.index(after: newIndex)
        }
        return newIndex
    }

    // MARK: Parsing

    private struct Parsed {
        var internationalPrefix = ""   // "", "+" or "00"
        var region: PhoneRegion?
        var callingCode = ""
        var trunk = ""
        var trunkJoiner = ""
        var nationalNumber = ""

        var isInternational: Bool { !internationalPrefix.isEmpty }
    }

    private static func formatted(_ raw: String, defaultRegion: String?) -> String? {
        let trimmed = raw.trimmed
        let fallback = defaultRegion ?? Locale.current.region?.identifier
        guard let parsed = parse(trimmed, defaultRegion: fallback) else { return nil }
        return rendered(parsed)
    }

    private static func parse(_ input: String, defaultRegion: String?) -> Parsed? {
        guard !input.isEmpty else { return nil }

        var sawPlus = false
        var number = ""
        for character in input {
            if digits.contains(character) {
                number.append(character)
            } else if character == "+" {
                // Only a leading + marks an international number; a + anywhere
                // else means this is some other kind of text.
                guard !sawPlus, number.isEmpty else { return nil }
                sawPlus = true
            } else if !punctuation.contains(character) {
                return nil
            }
        }

        var parsed = Parsed()
        if sawPlus {
            parsed.internationalPrefix = "+"
        } else if number.hasPrefix("00"), number.count > 2 {
            parsed.internationalPrefix = "00"
            number.removeFirst(2)
        }

        if parsed.isInternational {
            guard let (region, rest) = splitCallingCode(number) else {
                parsed.nationalNumber = number   // country not identifiable yet
                return parsed
            }
            parsed.region = region
            parsed.callingCode = region.callingCode
            var national = rest
            // People write +44 (0)7911…; a trunk code isn't part of the
            // international form. Only 0-style trunks are safe to drop: +7 800
            // numbers really do start with Russia's trunk digit. Taking every
            // leading zero, not just one, is what keeps reformatting settled:
            // whatever comes back out parses to the same number.
            if region.trunkPrefix.hasPrefix("0") {
                if national.hasPrefix(region.trunkPrefix) {
                    national.removeFirst(region.trunkPrefix.count)
                }
                while national.hasPrefix("0") {
                    national.removeFirst()
                }
            }
            parsed.nationalNumber = national
            return parsed
        }

        // Written the local way, so group it using the device's own region.
        let region = defaultRegion.flatMap { self.region(iso: $0) }
        parsed.region = region
        if let region, !region.trunkPrefix.isEmpty, number.hasPrefix(region.trunkPrefix) {
            parsed.trunk = region.trunkPrefix
            parsed.trunkJoiner = region.trunkJoiner
            number.removeFirst(region.trunkPrefix.count)
        }
        parsed.nationalNumber = number
        return parsed
    }

    private static func rendered(_ parsed: Parsed) -> String {
        let grouped = group(parsed.nationalNumber, in: parsed.region)
        if parsed.isInternational {
            let head = parsed.internationalPrefix + parsed.callingCode
            guard !grouped.isEmpty else { return head }
            return parsed.callingCode.isEmpty ? head + grouped : head + " " + grouped
        }
        guard !parsed.trunk.isEmpty else { return grouped }
        return grouped.isEmpty ? parsed.trunk : parsed.trunk + parsed.trunkJoiner + grouped
    }

    // MARK: Grouping

    private static func group(_ national: String, in region: PhoneRegion?) -> String {
        guard !national.isEmpty else { return "" }
        guard let region, let template = template(for: national, in: region) else {
            return genericGrouping(national)
        }
        return apply(template.pattern, to: national)
    }

    /// The template the number has reached: an exact-length match if it is
    /// complete, otherwise the first one long enough to hold what's typed.
    private static func template(for national: String, in region: PhoneRegion) -> PhoneTemplate? {
        let count = national.count
        if let exact = region.templates.first(where: { $0.digitCount == count && $0.accepts(national) }) {
            return exact
        }
        return region.templates.first { $0.digitCount > count && $0.accepts(national) }
    }

    private static func apply(_ pattern: String, to national: String) -> String {
        var result = ""
        var pending = ""            // separators held back until a digit arrives
        var remaining = Substring(national)

        for character in pattern {
            guard character == "#" else {
                pending.append(character)
                continue
            }
            guard let digit = remaining.first else { break }
            remaining = remaining.dropFirst()
            result += pending
            pending = ""
            result.append(digit)
        }

        // Close a bracket the number opened, so "(415" reads as "(415)".
        // Leave any other separator until the digit it divides is typed.
        if let closing = pending.lastIndex(of: ")") {
            result += pending[...closing]
        }
        if !remaining.isEmpty {
            result += " " + remaining   // longer than expected; keep every digit
        }
        // A half-typed area code shouldn't sit inside a bracket that never closes.
        if result.hasPrefix("("), !result.contains(")") {
            result.removeFirst()
        }
        return result
    }

    /// Threes, with the tail rolled into a group of four rather than left as a
    /// stray digit. Used where there's no hand-written rule for the country.
    private static func genericGrouping(_ national: String) -> String {
        var groups: [String] = []
        var remaining = Substring(national)
        while remaining.count > 4 {
            groups.append(String(remaining.prefix(3)))
            remaining = remaining.dropFirst(3)
        }
        if !remaining.isEmpty { groups.append(String(remaining)) }
        return groups.joined(separator: " ")
    }

    private static func digitCount(of text: String) -> Int {
        text.reduce(0) { digits.contains($1) ? $0 + 1 : $0 }
    }

    // MARK: Region lookup

    private static func splitCallingCode(_ number: String) -> (PhoneRegion, String)? {
        // Calling codes are prefix-free, so the longest match is the right one.
        for length in stride(from: 3, through: 1, by: -1) where number.count >= length {
            let code = String(number.prefix(length))
            if let region = byCallingCode[code] {
                return (region, String(number.dropFirst(length)))
            }
        }
        return nil
    }

    private static func region(iso: String) -> PhoneRegion? {
        byISO[iso.uppercased()]
    }

    /// Codes shared by several countries need the national number to tell them
    /// apart: the area code across the North American plan, the leading digit
    /// between Russia and Kazakhstan.
    private static func narrowed(_ region: PhoneRegion, nationalNumber: String) -> PhoneRegion {
        var narrowed = region
        switch region.callingCode {
        case "1":
            let area = String(nationalNumber.prefix(3))
            guard area.count == 3, let iso = nanpAreaCodes[area] else { return region }
            narrowed.iso = iso
        case "7":
            guard let first = nationalNumber.first, first == "6" || first == "7" else { return region }
            narrowed.iso = "KZ"
        default:
            return region
        }
        return narrowed
    }

    private static let byCallingCode: [String: PhoneRegion] = {
        var map: [String: PhoneRegion] = [:]
        for region in regionTable {
            map[region.callingCode] = region
        }
        for (code, iso) in plainCallingCodes where map[code] == nil {
            map[code] = PhoneRegion(iso: iso, callingCode: code)
        }
        return map
    }()

    private static let byISO: [String: PhoneRegion] = {
        var map: [String: PhoneRegion] = [:]
        for (code, iso) in plainCallingCodes {
            map[iso] = PhoneRegion(iso: iso, callingCode: code)
        }
        for region in regionTable {
            map[region.iso] = region
        }
        // Everyone on the North American plan shares its grouping.
        if let nanp = regionTable.first(where: { $0.callingCode == "1" }) {
            for iso in Set(nanpAreaCodes.values) {
                map[iso] = PhoneRegion(
                    iso: iso,
                    callingCode: "1",
                    trunkPrefix: nanp.trunkPrefix,
                    trunkJoiner: nanp.trunkJoiner,
                    templates: nanp.templates
                )
            }
        }
        return map
    }()
}

// MARK: - Grouping rules

private extension PhoneNumberFormatter {

    /// Countries with hand-checked grouping. Templates are listed most
    /// specific first, since the first match wins.
    static let regionTable: [PhoneRegion] = [
        // The North American plan is the one that brackets the area code.
        PhoneRegion(iso: "US", callingCode: "1", trunkPrefix: "1", trunkJoiner: " ", templates: [
            PhoneTemplate("(###) ###-####"),
            PhoneTemplate("###-####")
        ]),
        PhoneRegion(iso: "RU", callingCode: "7", trunkPrefix: "8", trunkJoiner: " ", templates: [
            PhoneTemplate("### ###-##-##")
        ]),
        PhoneRegion(iso: "EG", callingCode: "20", trunkPrefix: "0", templates: [
            PhoneTemplate("## #### ####", prefixes: ["1"]),
            PhoneTemplate("# #### ####", prefixes: ["2", "3"]),
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "ZA", callingCode: "27", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "GR", callingCode: "30", templates: [
            PhoneTemplate("### ### ####")
        ]),
        PhoneRegion(iso: "NL", callingCode: "31", trunkPrefix: "0", templates: [
            PhoneTemplate("# ########", prefixes: ["6"]),
            PhoneTemplate("## ### ####", prefixes: ["10", "13", "14", "15", "20", "23", "24", "26",
                                                    "30", "33", "35", "36", "38", "40", "43", "45",
                                                    "46", "50", "53", "55", "58", "70", "71", "72",
                                                    "73", "74", "75", "76", "77", "78", "79"]),
            PhoneTemplate("### ######")
        ]),
        PhoneRegion(iso: "BE", callingCode: "32", trunkPrefix: "0", templates: [
            PhoneTemplate("### ## ## ##", prefixes: ["4"]),
            PhoneTemplate("# ### ## ##", prefixes: ["2", "3", "4", "9"]),
            PhoneTemplate("## ### ## ##")
        ]),
        PhoneRegion(iso: "FR", callingCode: "33", trunkPrefix: "0", templates: [
            PhoneTemplate("# ## ## ## ##")
        ]),
        PhoneRegion(iso: "ES", callingCode: "34", templates: [
            PhoneTemplate("### ## ## ##")
        ]),
        PhoneRegion(iso: "HU", callingCode: "36", trunkPrefix: "06", trunkJoiner: " ", templates: [
            PhoneTemplate("## ### ####", prefixes: ["20", "30", "31", "50", "70"]),
            PhoneTemplate("# ### ####", prefixes: ["1"]),
            PhoneTemplate("## ### ###")
        ]),
        // Italian numbers keep their leading 0. There's no trunk code to strip.
        PhoneRegion(iso: "IT", callingCode: "39", templates: [
            PhoneTemplate("### #######", prefixes: ["3"]),
            PhoneTemplate("### ######", prefixes: ["3"]),
            PhoneTemplate("## #### ####", prefixes: ["02", "06"]),
            PhoneTemplate("## ### ####", prefixes: ["02", "06"]),
            PhoneTemplate("### ### ####"),
            PhoneTemplate("### ######")
        ]),
        PhoneRegion(iso: "RO", callingCode: "40", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "CH", callingCode: "41", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ## ##")
        ]),
        PhoneRegion(iso: "AT", callingCode: "43", trunkPrefix: "0", templates: [
            PhoneTemplate("# #######", prefixes: ["1"]),
            PhoneTemplate("### #######"),
            PhoneTemplate("### ######")
        ]),
        PhoneRegion(iso: "GB", callingCode: "44", trunkPrefix: "0", templates: [
            PhoneTemplate("## #### ####", prefixes: ["20", "23", "24", "28", "29"]),
            PhoneTemplate("### ### ####", prefixes: ["113", "114", "115", "116", "117", "118",
                                                    "121", "131", "141", "151", "161", "191"]),
            PhoneTemplate("#### ######", prefixes: ["7"]),
            PhoneTemplate("### ######", prefixes: ["800"]),
            PhoneTemplate("### ### ####", prefixes: ["3", "8", "9"]),
            PhoneTemplate("#### ######"),
            PhoneTemplate("#### #####")
        ]),
        PhoneRegion(iso: "DK", callingCode: "45", templates: [
            PhoneTemplate("## ## ## ##")
        ]),
        PhoneRegion(iso: "SE", callingCode: "46", trunkPrefix: "0", templates: [
            PhoneTemplate("##-### ## ##", prefixes: ["7"]),
            PhoneTemplate("#-### ## ##", prefixes: ["8"]),
            PhoneTemplate("##-### ## ##"),
            PhoneTemplate("##-## ## ##")
        ]),
        PhoneRegion(iso: "NO", callingCode: "47", templates: [
            PhoneTemplate("### ## ###", prefixes: ["4", "9"]),
            PhoneTemplate("## ## ## ##")
        ]),
        PhoneRegion(iso: "PL", callingCode: "48", templates: [
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "DE", callingCode: "49", trunkPrefix: "0", templates: [
            PhoneTemplate("### ########", prefixes: ["15", "16", "17"]),
            PhoneTemplate("### #######", prefixes: ["15", "16", "17"]),
            PhoneTemplate("## ########", prefixes: ["30", "40", "69", "89"]),
            PhoneTemplate("## #######", prefixes: ["30", "40", "69", "89"]),
            PhoneTemplate("### ########"),
            PhoneTemplate("### #######"),
            PhoneTemplate("### ######"),
            PhoneTemplate("### #####")
        ]),
        PhoneRegion(iso: "PE", callingCode: "51", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ###")
        ]),
        // Mexico dropped its 01 trunk code in 2019.
        PhoneRegion(iso: "MX", callingCode: "52", templates: [
            PhoneTemplate("## #### ####", prefixes: ["33", "55", "56", "81"]),
            PhoneTemplate("### ### ####")
        ]),
        PhoneRegion(iso: "AR", callingCode: "54", trunkPrefix: "0", templates: [
            PhoneTemplate("## ####-####", prefixes: ["11"]),
            PhoneTemplate("### ###-####"),
            PhoneTemplate("### ####-####")
        ]),
        PhoneRegion(iso: "BR", callingCode: "55", templates: [
            PhoneTemplate("(##) #####-####"),
            PhoneTemplate("(##) ####-####")
        ]),
        PhoneRegion(iso: "CL", callingCode: "56", trunkPrefix: "0", templates: [
            PhoneTemplate("# #### ####")
        ]),
        PhoneRegion(iso: "CO", callingCode: "57", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ####")
        ]),
        PhoneRegion(iso: "MY", callingCode: "60", trunkPrefix: "0", templates: [
            PhoneTemplate("##-#### ####", prefixes: ["1"]),
            PhoneTemplate("##-### ####", prefixes: ["1"]),
            PhoneTemplate("#-#### ####")
        ]),
        PhoneRegion(iso: "AU", callingCode: "61", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ###", prefixes: ["4"]),
            PhoneTemplate("# #### ####", prefixes: ["2", "3", "7", "8"]),
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "ID", callingCode: "62", trunkPrefix: "0", templates: [
            PhoneTemplate("### #### ####", prefixes: ["8"]),
            PhoneTemplate("### #### ###", prefixes: ["8"]),
            PhoneTemplate("## #### ####", prefixes: ["21"]),
            PhoneTemplate("### ### ####")
        ]),
        PhoneRegion(iso: "PH", callingCode: "63", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ####", prefixes: ["9"]),
            PhoneTemplate("# #### ####", prefixes: ["2"]),
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "NZ", callingCode: "64", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####", prefixes: ["2"]),
            PhoneTemplate("## ### ###", prefixes: ["2"]),
            PhoneTemplate("# ### ####")
        ]),
        PhoneRegion(iso: "SG", callingCode: "65", templates: [
            PhoneTemplate("#### ####")
        ]),
        PhoneRegion(iso: "TH", callingCode: "66", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####", prefixes: ["6", "8", "9"]),
            PhoneTemplate("# ### ####")
        ]),
        PhoneRegion(iso: "JP", callingCode: "81", trunkPrefix: "0", templates: [
            PhoneTemplate("##-####-####", prefixes: ["70", "80", "90"]),
            PhoneTemplate("#-####-####", prefixes: ["3", "6"]),
            PhoneTemplate("##-###-####")
        ]),
        PhoneRegion(iso: "KR", callingCode: "82", trunkPrefix: "0", templates: [
            PhoneTemplate("##-####-####", prefixes: ["10"]),
            PhoneTemplate("#-####-####", prefixes: ["2"]),
            PhoneTemplate("#-###-####", prefixes: ["2"]),
            PhoneTemplate("##-###-####")
        ]),
        PhoneRegion(iso: "VN", callingCode: "84", trunkPrefix: "0", templates: [
            PhoneTemplate("## #### ####", prefixes: ["24", "28"]),
            PhoneTemplate("### ### ###"),
            PhoneTemplate("### ### ####")
        ]),
        PhoneRegion(iso: "CN", callingCode: "86", trunkPrefix: "0", templates: [
            PhoneTemplate("### #### ####", prefixes: ["1"]),
            PhoneTemplate("## #### ####", prefixes: ["10", "20", "21", "22", "23", "24", "25",
                                                    "27", "28", "29"]),
            PhoneTemplate("### #### ####"),
            PhoneTemplate("### #### ###")
        ]),
        PhoneRegion(iso: "TR", callingCode: "90", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ## ##")
        ]),
        PhoneRegion(iso: "IN", callingCode: "91", trunkPrefix: "0", templates: [
            PhoneTemplate("##### #####")
        ]),
        PhoneRegion(iso: "PK", callingCode: "92", trunkPrefix: "0", templates: [
            PhoneTemplate("### #######")
        ]),
        PhoneRegion(iso: "LK", callingCode: "94", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "MA", callingCode: "212", trunkPrefix: "0", templates: [
            PhoneTemplate("# ## ## ## ##")
        ]),
        PhoneRegion(iso: "GH", callingCode: "233", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "NG", callingCode: "234", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ####"),
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "KE", callingCode: "254", trunkPrefix: "0", templates: [
            PhoneTemplate("### ######")
        ]),
        PhoneRegion(iso: "PT", callingCode: "351", templates: [
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "IE", callingCode: "353", trunkPrefix: "0", templates: [
            PhoneTemplate("# ### ####", prefixes: ["1"]),
            PhoneTemplate("## ### ####", prefixes: ["8"]),
            PhoneTemplate("## ### ####"),
            PhoneTemplate("## ######")
        ]),
        PhoneRegion(iso: "IS", callingCode: "354", templates: [
            PhoneTemplate("### ####")
        ]),
        PhoneRegion(iso: "FI", callingCode: "358", trunkPrefix: "0", templates: [
            PhoneTemplate("## #### ####", prefixes: ["4", "5"]),
            PhoneTemplate("## ### ####", prefixes: ["4", "5"]),
            PhoneTemplate("# ### ####", prefixes: ["9"]),
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "BG", callingCode: "359", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "UA", callingCode: "380", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ## ##")
        ]),
        PhoneRegion(iso: "RS", callingCode: "381", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####"),
            PhoneTemplate("## ### ###")
        ]),
        PhoneRegion(iso: "HR", callingCode: "385", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####"),
            PhoneTemplate("## ### ###")
        ]),
        PhoneRegion(iso: "CZ", callingCode: "420", templates: [
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "SK", callingCode: "421", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ###")
        ]),
        PhoneRegion(iso: "HK", callingCode: "852", templates: [
            PhoneTemplate("#### ####")
        ]),
        PhoneRegion(iso: "MO", callingCode: "853", templates: [
            PhoneTemplate("#### ####")
        ]),
        PhoneRegion(iso: "BD", callingCode: "880", trunkPrefix: "0", templates: [
            PhoneTemplate("#### ######")
        ]),
        PhoneRegion(iso: "TW", callingCode: "886", trunkPrefix: "0", templates: [
            PhoneTemplate("### ### ###", prefixes: ["9"]),
            PhoneTemplate("# #### ####", prefixes: ["2"]),
            PhoneTemplate("## ### ####")
        ]),
        PhoneRegion(iso: "LB", callingCode: "961", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ###")
        ]),
        PhoneRegion(iso: "IL", callingCode: "972", trunkPrefix: "0", templates: [
            PhoneTemplate("##-###-####", prefixes: ["5", "7"]),
            PhoneTemplate("#-###-####")
        ]),
        PhoneRegion(iso: "AE", callingCode: "971", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####"),
            PhoneTemplate("# ### ####")
        ]),
        PhoneRegion(iso: "SA", callingCode: "966", trunkPrefix: "0", templates: [
            PhoneTemplate("## ### ####"),
            PhoneTemplate("# ### ####")
        ]),
        PhoneRegion(iso: "QA", callingCode: "974", templates: [
            PhoneTemplate("#### ####")
        ]),
        PhoneRegion(iso: "KW", callingCode: "965", templates: [
            PhoneTemplate("#### ####")
        ]),
        PhoneRegion(iso: "BH", callingCode: "973", templates: [
            PhoneTemplate("#### ####")
        ]),
        PhoneRegion(iso: "OM", callingCode: "968", templates: [
            PhoneTemplate("#### ####")
        ])
    ]

    /// Every remaining calling code, so any `+` number can still name its
    /// country even without a grouping rule of its own.
    static let plainCallingCodes: [String: String] = [
        "1": "US", "7": "RU", "20": "EG", "27": "ZA", "30": "GR", "31": "NL", "32": "BE",
        "33": "FR", "34": "ES", "36": "HU", "39": "IT", "40": "RO", "41": "CH", "43": "AT",
        "44": "GB", "45": "DK", "46": "SE", "47": "NO", "48": "PL", "49": "DE", "51": "PE",
        "52": "MX", "53": "CU", "54": "AR", "55": "BR", "56": "CL", "57": "CO", "58": "VE",
        "60": "MY", "61": "AU", "62": "ID", "63": "PH", "64": "NZ", "65": "SG", "66": "TH",
        "81": "JP", "82": "KR", "84": "VN", "86": "CN", "90": "TR", "91": "IN", "92": "PK",
        "93": "AF", "94": "LK", "95": "MM", "98": "IR",
        "211": "SS", "212": "MA", "213": "DZ", "216": "TN", "218": "LY", "220": "GM",
        "221": "SN", "222": "MR", "223": "ML", "224": "GN", "225": "CI", "226": "BF",
        "227": "NE", "228": "TG", "229": "BJ", "230": "MU", "231": "LR", "232": "SL",
        "233": "GH", "234": "NG", "235": "TD", "236": "CF", "237": "CM", "238": "CV",
        "239": "ST", "240": "GQ", "241": "GA", "242": "CG", "243": "CD", "244": "AO",
        "245": "GW", "246": "IO", "248": "SC", "249": "SD", "250": "RW", "251": "ET",
        "252": "SO", "253": "DJ", "254": "KE", "255": "TZ", "256": "UG", "257": "BI",
        "258": "MZ", "260": "ZM", "261": "MG", "262": "RE", "263": "ZW", "264": "NA",
        "265": "MW", "266": "LS", "267": "BW", "268": "SZ", "269": "KM", "290": "SH",
        "291": "ER", "297": "AW", "298": "FO", "299": "GL",
        "350": "GI", "351": "PT", "352": "LU", "353": "IE", "354": "IS", "355": "AL",
        "356": "MT", "357": "CY", "358": "FI", "359": "BG", "370": "LT", "371": "LV",
        "372": "EE", "373": "MD", "374": "AM", "375": "BY", "376": "AD", "377": "MC",
        "378": "SM", "380": "UA", "381": "RS", "382": "ME", "383": "XK", "385": "HR",
        "386": "SI", "387": "BA", "389": "MK",
        "420": "CZ", "421": "SK", "423": "LI",
        "500": "FK", "501": "BZ", "502": "GT", "503": "SV", "504": "HN", "505": "NI",
        "506": "CR", "507": "PA", "508": "PM", "509": "HT", "590": "GP", "591": "BO",
        "592": "GY", "593": "EC", "594": "GF", "595": "PY", "596": "MQ", "597": "SR",
        "598": "UY", "599": "CW",
        "670": "TL", "672": "NF", "673": "BN", "674": "NR", "675": "PG", "676": "TO",
        "677": "SB", "678": "VU", "679": "FJ", "680": "PW", "681": "WF", "682": "CK",
        "683": "NU", "685": "WS", "686": "KI", "687": "NC", "688": "TV", "689": "PF",
        "690": "TK", "691": "FM", "692": "MH",
        "850": "KP", "852": "HK", "853": "MO", "855": "KH", "856": "LA", "880": "BD",
        "886": "TW",
        "960": "MV", "961": "LB", "962": "JO", "963": "SY", "964": "IQ", "965": "KW",
        "966": "SA", "967": "YE", "968": "OM", "970": "PS", "971": "AE", "972": "IL",
        "973": "BH", "974": "QA", "975": "BT", "976": "MN", "977": "NP", "992": "TJ",
        "993": "TM", "994": "AZ", "995": "GE", "996": "KG", "998": "UZ"
    ]

    /// +1 covers twenty-odd countries; the area code is what tells them apart.
    /// Anything unlisted is the United States.
    static let nanpAreaCodes: [String: String] = [
        // Canada
        "204": "CA", "226": "CA", "236": "CA", "249": "CA", "250": "CA", "263": "CA",
        "289": "CA", "306": "CA", "343": "CA", "354": "CA", "365": "CA", "367": "CA",
        "368": "CA", "382": "CA", "387": "CA", "403": "CA", "416": "CA", "418": "CA",
        "428": "CA", "431": "CA", "437": "CA", "438": "CA", "450": "CA", "468": "CA",
        "474": "CA", "506": "CA", "514": "CA", "519": "CA", "548": "CA", "579": "CA",
        "581": "CA", "584": "CA", "587": "CA", "604": "CA", "613": "CA", "639": "CA",
        "647": "CA", "672": "CA", "683": "CA", "705": "CA", "709": "CA", "742": "CA",
        "753": "CA", "778": "CA", "780": "CA", "782": "CA", "807": "CA", "819": "CA",
        "825": "CA", "867": "CA", "873": "CA", "879": "CA", "902": "CA", "905": "CA",
        // Caribbean and US territories
        "242": "BS", "246": "BB", "264": "AI", "268": "AG", "284": "VG", "340": "VI",
        "345": "KY", "441": "BM", "473": "GD", "649": "TC", "658": "JM", "664": "MS",
        "670": "MP", "671": "GU", "684": "AS", "721": "SX", "758": "LC", "767": "DM",
        "784": "VC", "787": "PR", "809": "DO", "829": "DO", "849": "DO", "868": "TT",
        "869": "KN", "876": "JM", "939": "PR"
    ]
}
