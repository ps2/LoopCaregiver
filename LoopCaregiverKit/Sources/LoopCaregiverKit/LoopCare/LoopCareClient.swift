//
//  LoopCareClient.swift
//  LoopCaregiverKit
//
//  Talking to a LoopCare node as a caregiver: opening and accepting an
//  invitation, and requests signed with the caregiver's key (x-lc-key,
//  x-lc-time, x-lc-sig), so no password or session is ever stored.
//

import Foundation

/// An invitation link from Loop: https://<site>/i/<inviteID>#<secret>. The secret after # never reaches the site.
public struct LoopCareInvitationLink: Equatable, Identifiable {
    public var id: String { inviteID }
    public let siteURL: URL
    public let inviteID: String
    public let secret: String

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["https", "http"].contains(scheme), let host = url.host,
              let secret = url.fragment, !secret.isEmpty
        else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "i", parts[1].count >= 8 else { return nil }
        // Plain http only for a node on this machine (development).
        guard scheme == "https" || host == "localhost" || host == "127.0.0.1" else { return nil }
        var site = URLComponents()
        site.scheme = scheme
        site.host = host
        site.port = url.port
        guard let siteURL = site.url else { return nil }
        self.siteURL = siteURL
        self.inviteID = String(parts[1])
        self.secret = secret
    }
}

/// What the invitation offers, as the site describes it.
public struct LoopCareInvitation {
    public let link: LoopCareInvitationLink
    public let circle: String
    /// The child's name in the circle, if Loop gave one.
    public let name: String?
    /// What Loop will call this caregiver.
    public let nickname: String
    public let relationship: String?
    /// pending, accepted, confirmed, cancelled or expired.
    public let status: String
    public let expires: Date?
    /// Who accepted it already, if anyone (a key ID).
    public let acceptedBy: String?
    /// What it lets the caregiver see: full, summary, safetyNet or review.
    public let visibility: String?
    /// What it lets the caregiver do, by area (meals, bolus, adjustments, settings, devices): none, approval, notify or full.
    public let areas: [String: String]
}

public enum LoopCareClientError: LocalizedError {
    case invalidLink
    case badResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidLink: return "That isn't a LoopCare invitation link. It looks like https://…/i/…#…"
        case .badResponse(_, let message): return message.isEmpty ? "The LoopCare site didn't accept that." : message
        }
    }
}

public struct LoopCareClient {
    public let key: CaregiverKey
    private let session: URLSession

    public init(key: CaregiverKey, session: URLSession = .shared) {
        self.key = key
        self.session = session
    }

    /// Opens an invitation: what it offers, and whether it's still open.
    public func open(_ link: LoopCareInvitationLink) async throws -> LoopCareInvitation {
        let info = try await send(base: link.siteURL, method: "GET", path: "/v1/invites/\(link.inviteID)", body: nil, headers: ["x-lc-invite-secret": link.secret], signed: false)
        guard let circle = info["circle"]?.stringValue else { throw LoopCareClientError.badResponse(200, "The invitation is missing its circle.") }
        let offered = info["offered"]
        var areas: [String: String] = [:]
        for (area, level) in offered?["areas"]?.objectValue ?? [:] { areas[area] = level.stringValue }
        return LoopCareInvitation(
            link: link, circle: circle, name: info["name"]?.stringValue,
            nickname: info["nickname"]?.stringValue ?? "Caregiver", relationship: info["relationship"]?.stringValue,
            status: info["status"]?.stringValue ?? "pending",
            expires: info["expires"]?.stringValue.flatMap(Self.parseDate),
            acceptedBy: info["acceptedBy"]?.stringValue, visibility: offered?["visibility"]?.stringValue, areas: areas)
    }

    /// Accepts with this caregiver's key. Loop then has to confirm them before they see anything.
    public func accept(_ invitation: LoopCareInvitation, now: Date = Date()) async throws {
        let link = invitation.link
        let k = "\(invitation.circle)/invite/\(link.inviteID)/acceptance"
        let event = try key.sign(event: [
            "id": .string("\(k)@\(key.keyID)"), "circle": .string(invitation.circle), "type": "invite.accepted", "key": .string(k), "version": 1,
            "at": .string(LoopCareSigning.isoString(now)),
            "data": [
                "inviteId": .string(link.inviteID), "keyId": .string(key.keyID), "publicKey": key.publicJWK,
                "secretProof": .string(LoopCareSigning.acceptanceProof(secret: link.secret, inviteID: link.inviteID, keyID: key.keyID)),
            ],
        ])
        _ = try await send(base: link.siteURL, method: "POST", path: "/v1/invites/\(link.inviteID)/accept", body: ["secret": .string(link.secret), "event": event], signed: false)
    }

    /// A request as this caregiver, signed with their key.
    public func request(base: URL, method: String, path: String, body: LoopCareJSON? = nil) async throws -> LoopCareJSON {
        try await send(base: base, method: method, path: path, body: body, signed: true)
    }

    private func send(base: URL, method: String, path: String, body: LoopCareJSON?, headers: [String: String] = [:], signed: Bool) async throws -> LoopCareJSON {
        guard let url = URL(string: path, relativeTo: base) else { throw LoopCareClientError.invalidLink }
        let data = body?.canonicalData ?? Data()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        for (name, value) in headers { req.setValue(value, forHTTPHeaderField: name) }
        if signed {
            let time = String(Int64(Date().timeIntervalSince1970 * 1000))
            req.setValue(key.keyID, forHTTPHeaderField: "x-lc-key")
            req.setValue(time, forHTTPHeaderField: "x-lc-time")
            req.setValue(try key.sign(Data(LoopCareSigning.signingString(method: method, pathAndQuery: path, time: time, body: data).utf8)), forHTTPHeaderField: "x-lc-sig")
        }
        if body != nil {
            req.httpBody = data
            req.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        let (respData, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? LoopCareJSON.parse(respData)) ?? .null
        guard (200..<300).contains(status) else {
            throw LoopCareClientError.badResponse(status, json["error"]?.stringValue ?? "")
        }
        return json
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
