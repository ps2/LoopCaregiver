//
//  CaregiverKey.swift
//  LoopCaregiverKit
//
//  The caregiver's own key (LoopSight design §5): a P-256 key that signs their
//  acceptance of an invitation, their requests and their commands to Loop.
//  Loop's grant names its key ID, so only this key acts as this caregiver.
//  One key for every circle this caregiver joins; kept in iCloud Keychain, so
//  the caregiver's other devices on the same Apple ID are the same person.
//

import CryptoKit
import Foundation
import Security

public struct CaregiverKey {
    public let privateKey: P256.Signing.PrivateKey

    public init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    public static func generate() -> CaregiverKey { CaregiverKey(privateKey: P256.Signing.PrivateKey()) }

    /// The public key as the JWK the server stores: {kty, crv, x, y}.
    public var publicJWK: LoopSightJSON {
        let x963 = privateKey.publicKey.x963Representation // 0x04 || X || Y
        return [
            "kty": "EC",
            "crv": "P-256",
            "x": .string(x963.subdata(in: 1..<33).base64URLEncoded),
            "y": .string(x963.subdata(in: 33..<65).base64URLEncoded),
        ]
    }

    /// The key's ID: base64url(SHA-256(canonical JWK)), first 22 characters.
    public var keyID: String { CaregiverKey.keyID(of: publicJWK) }

    public static func keyID(of jwk: LoopSightJSON) -> String {
        String(Data(SHA256.hash(data: jwk.canonicalData)).base64URLEncoded.prefix(22))
    }

    /// A signature as LoopSight expects: ECDSA P-256 over SHA-256, raw r||s, base64url.
    public func sign(_ data: Data) throws -> String {
        try privateKey.signature(for: data).rawRepresentation.base64URLEncoded
    }

    /// An event with `sig` added: the caregiver's signature over its signed bytes.
    public func sign(event: LoopSightJSON) throws -> LoopSightJSON {
        guard case .object(var members) = event else { return event }
        members["sig"] = .string(try sign(LoopSightSigning.signedBytes(of: event)))
        return .object(members)
    }
}

/// Where the caregiver key lives.
public enum CaregiverKeyStore {
    static let service = "org.loopkit.LoopCaregiver.LoopCare"
    static let account = "caregiver-key"

    /// The key, made the first time it's needed.
    public static func loadOrCreate() throws -> CaregiverKey {
        if let key = try load() { return key }
        let key = CaregiverKey.generate()
        try save(key)
        return key
    }

    public static func load() throws -> CaregiverKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status: status) }
        return CaregiverKey(privateKey: try P256.Signing.PrivateKey(rawRepresentation: data))
    }

    static func save(_ key: CaregiverKey) throws {
        var item = baseQuery
        item[kSecValueData as String] = key.privateKey.rawRepresentation
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]
    }

    public struct KeychainError: LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? { "The Keychain couldn't keep your LoopSight key (\(status))." }
    }
}

public enum LoopSightSigning {
    /// The bytes an event's signature covers: {id, circle, type, key, version, at, data}, canonical.
    public static func signedBytes(of event: LoopSightJSON) -> Data {
        var covered: [String: LoopSightJSON] = [:]
        for field in ["id", "circle", "type", "key", "version", "at", "data"] {
            if let v = event[field], v != .null { covered[field] = v }
        }
        return LoopSightJSON.object(covered).canonicalData
    }

    /// METHOD \n path?query \n time \n hex(SHA-256(body)).
    public static func signingString(method: String, pathAndQuery: String, time: String, body: Data) -> String {
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return "\(method)\n\(pathAndQuery)\n\(time)\n\(hash)"
    }

    /// Times as the server writes them (Date.toISOString): UTC, milliseconds, Z.
    public static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Proof, inside an acceptance, that it comes from someone holding the invitation link (LoopSight src/authority.js).
    public static func acceptanceProof(secret: String, inviteID: String, keyID: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("loopcare-accept\n\(inviteID)\n\(keyID)".utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return Data(mac).base64URLEncoded
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
