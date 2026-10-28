//
//  LoopSightJoin.swift
//  LoopCaregiverKit
//
//  Joining a circle from an invitation link: open it, accept with this
//  caregiver's key, and follow the child as a LoopSight Looper.
//

import Foundation

public extension AccountServiceManager {
    /// Accepts the invitation (unless this caregiver already did) and adds the child as a LoopSight Looper.
    /// Loop still has to confirm them; until then the Looper waits.
    @MainActor
    func join(_ invitation: LoopSightInvitation, name: String) async throws -> Looper {
        let key = try CaregiverKeyStore.loadOrCreate()
        if let looper = loopers.first(where: { $0.loopSightCredentials?.circle == invitation.circle }) {
            throw LoopSightJoinError.alreadyFollowing(looper.name)
        }
        switch invitation.status {
        case "cancelled": throw LoopSightJoinError.closed("This invitation was cancelled.")
        case "expired": throw LoopSightJoinError.closed("This invitation has expired. Ask for a new one.")
        default: break
        }
        if invitation.acceptedBy == nil {
            try await LoopSightClient(key: key).accept(invitation)
        } else if invitation.acceptedBy != key.keyID {
            throw LoopSightJoinError.closed("Someone else has already accepted this invitation.")
        }
        let looper = Looper(
            identifier: UUID(), name: name,
            backend: .loopSight(LoopSightCredentials(siteURL: invitation.link.siteURL, circle: invitation.circle, keyID: key.keyID)),
            lastSelectedDate: Date())
        try addLooper(looper)
        try updateActiveLoopUser(looper)
        return looper
    }
}

public enum LoopSightJoinError: LocalizedError {
    case alreadyFollowing(String)
    case closed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyFollowing(let name): return "You already follow this circle as \(name)."
        case .closed(let message): return message
        }
    }
}
