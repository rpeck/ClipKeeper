import Foundation

/// The kinds of possibly personal or secret data in a clip. Stored as an
/// integer bit mask in `clip.piiFlags`; 0 means scanned, nothing found, and
/// NULL means not scanned yet.
struct PersonalDataFlags: OptionSet, Hashable {
    let rawValue: Int

    static let email = PersonalDataFlags(rawValue: 1 << 0)
    static let phone = PersonalDataFlags(rawValue: 1 << 1)
    static let address = PersonalDataFlags(rawValue: 1 << 2)
    static let card = PersonalDataFlags(rawValue: 1 << 3)
    static let ssn = PersonalDataFlags(rawValue: 1 << 4)
    static let iban = PersonalDataFlags(rawValue: 1 << 5)
    static let secret = PersonalDataFlags(rawValue: 1 << 6)

    static let all: [(PersonalDataFlags, String)] = [
        (.email, "email address"), (.phone, "phone number"), (.address, "postal address"),
        (.card, "card number"), (.ssn, "Social Security number"), (.iban, "bank account (IBAN)"),
        (.secret, "password, key, or token"),
    ]

    /// "email address, phone number"
    var names: String {
        Self.all.filter { contains($0.0) }.map(\.1).joined(separator: ", ")
    }
}

/// Finds data that may be personal or secret, on this Mac only. Patterns are
/// specific on purpose, because many clips are code: a card number must pass
/// the Luhn check, an IBAN its check digits, and a secret must have the shape
/// of a known key format. Pattern matching misses some data and flags some
/// harmless text; it supports an audit and guarantees nothing.
enum PersonalDataDetector {
    /// Increase this when a rule changes. At launch, a new version clears the
    /// stored flags, so that every clip is scanned again.
    static let version = 2
    static let maxCharacters = 50_000
    static let budgetSeconds = 0.3

    static func detect(_ text: String) -> PersonalDataFlags {
        guard !text.isEmpty else { return [] }
        let sample = String(text.prefix(maxCharacters))
        let budget = DetectionSample.Budget(seconds: budgetSeconds)
        var flags: PersonalDataFlags = []
        let range = NSRange(sample.startIndex..., in: sample)

        if Patterns.email.firstMatch(in: sample, range: range) != nil { flags.insert(.email) }
        if budget.isExpired { return flags }

        for match in Patterns.ssn.matches(in: sample, range: range) {
            guard let r = Range(match.range, in: sample) else { continue }
            if isPlausibleSSN(String(sample[r])) { flags.insert(.ssn); break }
        }
        if budget.isExpired { return flags }

        for match in Patterns.card.matches(in: sample, range: range) {
            guard let r = Range(match.range, in: sample) else { continue }
            let digits = String(sample[r].filter(\.isNumber))
            if (13...19).contains(digits.count), hasCardPrefix(digits), luhn(digits) { flags.insert(.card); break }
        }
        if budget.isExpired { return flags }

        for match in Patterns.iban.matches(in: sample, range: range) {
            guard let r = Range(match.range, in: sample) else { continue }
            if ibanValid(String(sample[r])) { flags.insert(.iban); break }
        }
        if budget.isExpired { return flags }

        if Patterns.secrets.contains(where: { $0.firstMatch(in: sample, range: range) != nil }) { flags.insert(.secret) }
        if budget.isExpired { return flags }

        // Phone numbers and postal addresses: the system's data detector.
        if let detector = Patterns.dataDetector {
            for match in detector.matches(in: sample, range: range) {
                if match.resultType == .phoneNumber, let number = match.phoneNumber, number.filter(\.isNumber).count >= 10,
                   let r = Range(match.range, in: sample), isPlausiblePhone(String(sample[r])) {
                    flags.insert(.phone)
                }
                if match.resultType == .address { flags.insert(.address) }
                if budget.isExpired { break }
            }
        }
        return flags
    }

    // MARK: Checks

    /// The Luhn check digit, used by every payment card number.
    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
        }
        return sum % 10 == 0 && Set(digits).count > 1
    }

    /// The issuer prefix and length of the major card networks, so that a
    /// long number in code, such as a timestamp, is not taken for a card.
    static func hasCardPrefix(_ digits: String) -> Bool {
        func starts(_ low: Int, _ high: Int, _ width: Int) -> Bool {
            guard let value = Int(digits.prefix(width)) else { return false }
            return (low...high).contains(value)
        }
        switch digits.count {
        case 15: return starts(34, 34, 2) || starts(37, 37, 2)                       // American Express
        case 14: return starts(300, 305, 3) || starts(36, 36, 2) || starts(38, 39, 2) // Diners Club
        case 13, 16, 19:
            return digits.hasPrefix("4")                                              // Visa
                || starts(51, 55, 2) || starts(2_221, 2_720, 4)                      // Mastercard
                || digits.hasPrefix("6011") || starts(644, 649, 3) || digits.hasPrefix("65") // Discover
                || starts(3_528, 3_589, 4)                                           // JCB
        default: return false
        }
    }

    /// A written phone number: international, with a leading +, or in groups
    /// of at most 4 digits, such as (415) 555-0132. A bare run of digits is
    /// more often a timestamp or an id in code.
    static func isPlausiblePhone(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") { return true }
        let groups = trimmed.split { !$0.isNumber }
        return groups.count > 1 && groups.allSatisfy { $0.count <= 4 }
    }

    /// AAA-GG-SSSS, never issued with area 000, 666, or 900-999, group 00, or serial 0000.
    static func isPlausibleSSN(_ text: String) -> Bool {
        let parts = text.split(separator: "-").map(String.init)
        guard parts.count == 3, let area = Int(parts[0]), let group = Int(parts[1]), let serial = Int(parts[2]) else { return false }
        return area != 0 && area != 666 && area < 900 && group != 0 && serial != 0
    }

    /// ISO 13616: move the first four characters to the end, letters to
    /// numbers, and the result mod 97 must be 1.
    static func ibanValid(_ raw: String) -> Bool {
        let iban = raw.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(iban.count) else { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for ch in rearranged {
            if let d = ch.wholeNumberValue {
                remainder = (remainder * 10 + d) % 97
            } else if let ascii = ch.asciiValue, ch.isLetter {
                let value = Int(ascii) - 55   // A = 10
                remainder = (remainder * 100 + value) % 97
            } else {
                return false
            }
        }
        return remainder == 1
    }

    private enum Patterns {
        static let email = compileRegex(pattern: #"[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(\.[A-Za-z0-9-]{1,63})*\.[A-Za-z]{2,24}"#)
        static let ssn = compileRegex(pattern: #"(?<![0-9-])[0-9]{3}-[0-9]{2}-[0-9]{4}(?![0-9-])"#)
        static let card = compileRegex(pattern: #"(?<![0-9])[0-9](?:[ -]?[0-9]){12,18}(?![0-9])"#)
        static let iban = compileRegex(pattern: #"\b[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]){11,30}\b"#)
        static let secrets: [NSRegularExpression] = [
            #"(?<![A-Z0-9])AKIA[0-9A-Z]{16}(?![A-Z0-9])"#,           // AWS access key
            #"(?<![A-Za-z0-9])gh[pousr]_[A-Za-z0-9]{36,255}"#,      // GitHub tokens
            #"github_pat_[A-Za-z0-9_]{22,255}"#,
            // OpenAI and Anthropic keys. Not inside a word, such as "risk-",
            // and with a digit and a capital, which kebab-case names do not have.
            #"(?<![A-Za-z0-9_-])sk-(?:ant-|proj-)?(?=[A-Za-z0-9_-]{0,200}[0-9])(?=[A-Za-z0-9_-]{0,200}[A-Z])[A-Za-z0-9_-]{20,}"#,
            #"xox[abprs]-[A-Za-z0-9-]{10,}"#,                       // Slack tokens
            #"AIza[0-9A-Za-z_-]{35}"#,                              // Google API key
            #"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,   // JWT
            #"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"#,
        ].map { compileRegex(pattern: $0) }
        static let dataDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)
    }
}
