//
//  JoinLoopCareDeepLink.swift
//  LoopCaregiverKit
//
//  caregiver://loopcare-join?link=<invitation link>: how an invitation Loop
//  shared opens LoopCaregiver (from the invitation page's "Open in
//  LoopCaregiver" button). The app then shows what the invitation offers and
//  asks before joining. A plain https link can't open the app directly:
//  that needs the site to list every DIY build's team.
//

import Foundation

public struct JoinLoopCareDeepLink: DeepLink {
    public static let actionName = "loopcare-join"
    public let invitationLink: LoopCareInvitationLink
    public let url: URL

    public init(invitationLink: LoopCareInvitationLink, linkText: String) {
        self.invitationLink = invitationLink
        var components = URLComponents()
        components.scheme = Self.host
        components.host = Self.actionName
        components.queryItems = [URLQueryItem(name: "link", value: linkText)]
        self.url = components.url!
    }

    public init(pathParts: [String], queryParameters: [String: String]) throws {
        guard let text = queryParameters["link"], let link = LoopCareInvitationLink(text) else {
            throw Error.invalidLink
        }
        self.init(invitationLink: link, linkText: text)
    }

    public enum Error: LocalizedError {
        case invalidLink
        case phoneOnly

        public var errorDescription: String? {
            switch self {
            case .invalidLink: return "That LoopCare invitation link isn't complete. Ask for it again from Loop."
            case .phoneOnly: return "Open LoopCare invitations on your iPhone."
            }
        }
    }
}

public extension LoopCareInvitationLink {
    /// A link as Loop shares it (https://…/i/…#…), or the caregiver:// link that carries one.
    init?(anyLink text: String) {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == JoinLoopCareDeepLink.host,
           let deepLink = try? DeepLinkParser().parseDeepLink(url: url), case .joinLoopCare(let join) = deepLink {
            self = join.invitationLink
        } else if let link = LoopCareInvitationLink(text) {
            self = link
        } else {
            return nil
        }
    }

    /// The link as text, for showing in the app.
    var text: String { "\(siteURL.absoluteString)/i/\(inviteID)#\(secret)" }
}
