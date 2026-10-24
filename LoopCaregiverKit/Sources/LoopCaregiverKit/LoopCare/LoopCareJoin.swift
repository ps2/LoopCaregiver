//
//  LoopCareJoin.swift
//  LoopCaregiverKit
//
//  Joining a circle from an invitation link: open it, accept with this
//  caregiver's key, and follow the child as a LoopCare Looper.
//

import Foundation

public extension AccountServiceManager {
    /// Accepts the invitation (unless this caregiver already did) and adds the child as a LoopCare Looper.
    /// Loop still has to confirm them; until then the Looper waits.
    @MainActor
    func join(_ invitation: LoopCareInvitation, name: String) async throws -> Looper {
        let key = try CaregiverKeyStore.loadOrCreate()
        if let looper = loopers.first(where: { $0.loopCareCredentials?.circle == invitation.circle }) {
            throw LoopCareJoinError.alreadyFollowing(looper.name)
        }
        switch invitation.status {
        case "cancelled": throw LoopCareJoinError.closed("This invitation was cancelled.")
        case "expired": throw LoopCareJoinError.closed("This invitation has expired. Ask for a new one.")
        default: break
        }
        if invitation.acceptedBy == nil {
            try await LoopCareClient(key: key).accept(invitation)
        } else if invitation.acceptedBy != key.keyID {
            throw LoopCareJoinError.closed("Someone else has already accepted this invitation.")
        }
        let looper = Looper(
            identifier: UUID(), name: name,
            backend: .loopCare(LoopCareCredentials(siteURL: invitation.link.siteURL, circle: invitation.circle, keyID: key.keyID)),
            lastSelectedDate: Date())
        try addLooper(looper)
        try updateActiveLoopUser(looper)
        return looper
    }
}

public enum LoopCareJoinError: LocalizedError {
    case alreadyFollowing(String)
    case closed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyFollowing(let name): return "You already follow this circle as \(name)."
        case .closed(let message): return message
        }
    }
}
