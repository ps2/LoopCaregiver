//
//  Looper.swift
//
//
//  Created by Bill Gestrich on 5/11/22.
//

import Foundation

public class Looper: ObservableObject, Hashable, Codable, Identifiable {
    public var identifier: UUID
    public var name: String
    public var lastSelectedDate: Date
    /// Where this Looper's data and commands go.
    public let backend: LooperBackend

    public init(identifier: UUID, name: String, backend: LooperBackend, lastSelectedDate: Date) {
        self.identifier = identifier
        self.name = name
        self.lastSelectedDate = lastSelectedDate
        self.backend = backend
    }

    public convenience init(identifier: UUID, name: String, nightscoutCredentials: NightscoutCredentials, lastSelectedDate: Date) {
        self.init(identifier: identifier, name: name, backend: .nightscout(nightscoutCredentials), lastSelectedDate: lastSelectedDate)
    }

    /// The Nightscout site, for a Looper followed through Nightscout.
    public var nightscoutCredentials: NightscoutCredentials? {
        if case .nightscout(let credentials) = backend { return credentials }
        return nil
    }

    /// The LoopCare circle, for a Looper followed through LoopCare.
    public var loopCareCredentials: LoopCareCredentials? {
        if case .loopCare(let credentials) = backend { return credentials }
        return nil
    }

    // MARK: Codable (a Nightscout Looper encodes as before LoopCare)

    private enum CodingKeys: String, CodingKey {
        case identifier, name, lastSelectedDate, nightscoutCredentials, loopCareCredentials
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decode(UUID.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        lastSelectedDate = try container.decode(Date.self, forKey: .lastSelectedDate)
        if let loopCare = try container.decodeIfPresent(LoopCareCredentials.self, forKey: .loopCareCredentials) {
            backend = .loopCare(loopCare)
        } else {
            backend = .nightscout(try container.decode(NightscoutCredentials.self, forKey: .nightscoutCredentials))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(lastSelectedDate, forKey: .lastSelectedDate)
        switch backend {
        case .nightscout(let credentials): try container.encode(credentials, forKey: .nightscoutCredentials)
        case .loopCare(let credentials): try container.encode(credentials, forKey: .loopCareCredentials)
        }
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    // MARK: Equatable

    public static func == (lhs: Looper, rhs: Looper) -> Bool {
        // TODO: Equality should check other properties
        // See note in HUDViewModel.selectedLooper
        return lhs.identifier == rhs.identifier
    }

    // MARK: Identifiable
    // Conformance declaration is in LoopCaregiver app target
    // to keep SwiftUI out of LoopCaregiverKit

    public var id: String {
        return identifier.uuidString
    }
}

/// How the app reaches a Looper.
public enum LooperBackend: Codable, Hashable {
    /// The Looper's Nightscout site: data, and commands with Loop's one-time password.
    case nightscout(NightscoutCredentials)
    /// A child in a LoopCare circle: data, signed commands, alerts and the people caring for them.
    case loopCare(LoopCareCredentials)
}

/// A caregiver's membership in a LoopCare circle. The caregiver's private key stays in the Keychain, under `keyID`.
public struct LoopCareCredentials: Codable, Hashable {
    /// The LoopCare node this app talks to first.
    public let siteURL: URL
    /// The circle: one child's Loop.
    public let circle: String
    /// This caregiver's key ID, as the circle's grants name it.
    public let keyID: String

    public init(siteURL: URL, circle: String, keyID: String) {
        self.siteURL = siteURL
        self.circle = circle
        self.keyID = keyID
    }
}
