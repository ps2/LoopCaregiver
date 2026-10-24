//
//  LoopCareJSON.swift
//  LoopCaregiverKit (from LoopCareService)
//
//  A JSON value, and its canonical form: keys sorted (by UTF-16 code units),
//  no whitespace, numbers and strings written exactly as JavaScript's
//  JSON.stringify writes them. LoopCare signs canonical JSON, so this must
//  match the server byte for byte (LoopCare tools/test-vectors.js).
//

import Foundation

public enum LoopCareJSON: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([LoopCareJSON])
    case object([String: LoopCareJSON])

    public var canonical: String {
        var out = ""
        write(into: &out)
        return out
    }

    public var canonicalData: Data { Data(canonical.utf8) }

    private func write(into out: inout String) {
        switch self {
        case .string(let s): LoopCareJSON.writeString(s, into: &out)
        case .number(let n): out += LoopCareJSON.format(n)
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            let keys = members.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            for (i, key) in keys.enumerated() {
                if i > 0 { out += "," }
                LoopCareJSON.writeString(key, into: &out)
                out += ":"
                members[key]!.write(into: &out)
            }
            out += "}"
        }
    }

    /// As JSON.stringify: escapes quote, backslash and control characters; nothing else.
    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for unit in s.unicodeScalars {
            switch unit {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if unit.value < 0x20 {
                    out += String(format: "\\u%04x", unit.value)
                } else {
                    out.unicodeScalars.append(unit)
                }
            }
        }
        out += "\""
    }

    /// As JavaScript's Number.prototype.toString: the shortest round-trip digits,
    /// written as a plain decimal from 1e-7 up to 1e21, in exponent form outside it.
    static func format(_ n: Double) -> String {
        guard n.isFinite else { return "null" }
        if n == 0 { return "0" }
        if n == n.rounded(), abs(n) < 1e21 { return String(Int64(n)) }
        // Swift's description gives the shortest round-trip digits; take them and the exponent apart.
        let negative = n < 0
        let s = String(describing: abs(n)).lowercased()
        var mantissa = s
        var exponent = 0
        if let e = s.firstIndex(of: "e") {
            mantissa = String(s[..<e])
            exponent = Int(s[s.index(after: e)...].replacingOccurrences(of: "+", with: ""))!
        }
        // Digits without the point, and where the point goes (scientific: d.ddd × 10^exponent).
        let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = String(parts[0])
        let fracPart = parts.count > 1 ? String(parts[1]) : ""
        var digits = intPart + fracPart
        var point = intPart.count + exponent // position of the decimal point within digits
        while digits.hasPrefix("0"), digits.count > 1 { digits.removeFirst(); point -= 1 }
        while digits.hasSuffix("0"), digits.count > 1 { digits.removeLast() }
        let k = digits.count
        let sciExponent = point - 1
        var result: String
        if sciExponent >= 21 || sciExponent < -6 {
            let lead = digits.prefix(1)
            let rest = digits.dropFirst()
            result = String(lead) + (rest.isEmpty ? "" : "." + rest) + "e" + (sciExponent >= 0 ? "+" : "-") + String(abs(sciExponent))
        } else if point <= 0 {
            result = "0." + String(repeating: "0", count: -point) + digits
        } else if point >= k {
            result = digits + String(repeating: "0", count: point - k)
        } else {
            let i = digits.index(digits.startIndex, offsetBy: point)
            result = String(digits[..<i]) + "." + String(digits[i...])
        }
        return negative ? "-" + result : result
    }
}

extension LoopCareJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: LoopCareJSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, LoopCareJSON)...) { self = .object(Dictionary(elements, uniquingKeysWith: { $1 })) }
    public init(nilLiteral: ()) { self = .null }
}

public extension LoopCareJSON {
    /// From JSONSerialization's output (for reading the server's responses).
    init(any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let a as [Any]: self = .array(a.map(LoopCareJSON.init(any:)))
        case let o as [String: Any]: self = .object(o.mapValues(LoopCareJSON.init(any:)))
        default: self = .null
        }
    }

    static func parse(_ data: Data) throws -> LoopCareJSON {
        LoopCareJSON(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    subscript(key: String) -> LoopCareJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    var arrayValue: [LoopCareJSON]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: LoopCareJSON]? { if case .object(let o) = self { return o }; return nil }
}
