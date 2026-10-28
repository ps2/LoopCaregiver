//
//  LoopSightJoinTestCase.swift
//  LoopCaregiverKitTests
//
//  Joining a LoopSight circle. Signing must match the LoopSight server byte for
//  byte; the values here come from its tools/test-vectors.js. The end-to-end
//  test runs against a local demo node, which confirms caregivers itself:
//
//    DATA_DIR=./data/cg PUBLIC_URL=http://localhost:1362 RP_ID=localhost PORT=1362 node src/cli.js demo
//    TEST_RUNNER_LOOPSIGHT_INVITE="$(grep -o 'http[^ ]*' ./data/cg/demo-invites.txt | head -1)" xcodebuild test …
//

import CryptoKit
@testable import LoopCaregiverKit
import XCTest

final class LoopSightJoinTestCase: XCTestCase {
    func testAcceptanceProofMatchesTheServer() {
        XCTAssertEqual(LoopSightSigning.acceptanceProof(secret: "Zm9vYmFyLXNlY3JldC0xMjM0", inviteID: "abcdefgh12345678", keyID: "SvjY8OBS3TyNwynRQfOVRk"),
                       "xslMor5Vi2cUcW-ZTF1uoNun3sixT22OE33HAs9ffUk")
    }

    func testKeyIDAndCanonicalJSONMatchTheServer() {
        let jwk: LoopSightJSON = ["kty": "EC", "crv": "P-256", "x": "Iw2eBZS6ypsNQT6Cy5Wk7JsLhTgNUHzx_18I-j9Oc6w", "y": "u5akV7OSiVkqDyR9MA7tUy1h2tCye4_zpQR3KIjMnzI"]
        XCTAssertEqual(CaregiverKey.keyID(of: jwk), "FbV9pnIbxqMXD6EdkyIl7Q")
        let value: LoopSightJSON = ["é": "ünïcødé ✓", "Z": "quote \" backslash \\ slash / tab \t nl \n ctrl \u{0001}", "a": 110, "b": 110.5]
        XCTAssertEqual(value.canonical, #"{"Z":"quote \" backslash \\ slash / tab \t nl \n ctrl \u0001","a":110,"b":110.5,"é":"ünïcødé ✓"}"#)
    }

    func testInvitationLinks() throws {
        let link = try XCTUnwrap(LoopSightInvitationLink("  https://care.example.org/i/abcdefgh12345678#s3cret\n"))
        XCTAssertEqual(link.siteURL.absoluteString, "https://care.example.org")
        XCTAssertEqual(link.inviteID, "abcdefgh12345678")
        XCTAssertEqual(link.secret, "s3cret")
        XCTAssertEqual(LoopSightInvitationLink("http://localhost:1362/i/abcdefgh12345678#s")?.siteURL.absoluteString, "http://localhost:1362")
        XCTAssertNil(LoopSightInvitationLink("https://care.example.org/i/abcdefgh12345678"), "no secret")
        XCTAssertNil(LoopSightInvitationLink("http://care.example.org/i/abcdefgh12345678#s"), "plain http off this machine")
        XCTAssertNil(LoopSightInvitationLink("https://care.example.org/x/abcdefgh12345678#s"))
    }

    func testJoinDeepLink() throws {
        let text = "https://care.example.org/i/abcdefgh12345678#s3c/r+t="
        let link = try XCTUnwrap(LoopSightInvitationLink(text))
        let deepLink = JoinLoopSightDeepLink(invitationLink: link, linkText: text)
        XCTAssertEqual(deepLink.url.scheme, "caregiver")
        XCTAssertEqual(deepLink.url.host, "loopsight-join")

        // What the invitation page's button opens: the whole link, secret included, comes through.
        guard case .joinLoopSight(let parsed) = try DeepLinkParser().parseDeepLink(url: deepLink.url) else {
            return XCTFail("not a join link")
        }
        XCTAssertEqual(parsed.invitationLink, link)
        XCTAssertEqual(parsed.invitationLink.secret, "s3c/r+t=")
        // Either form works where a link is pasted or scanned.
        XCTAssertEqual(LoopSightInvitationLink(anyLink: deepLink.url.absoluteString), link)
        XCTAssertEqual(LoopSightInvitationLink(anyLink: text), link)
        XCTAssertThrowsError(try DeepLinkParser().parseDeepLink(url: URL(string: "caregiver://loopsight-join?link=nope")!))
    }

    func testJoinDeepLink_FromBeforeTheRename_StillParses() throws {
        let text = "https://care.example.org/i/abcdefgh12345678#s3c/r+t="
        var components = URLComponents(string: "caregiver://loopcare-join")!
        components.queryItems = [URLQueryItem(name: "link", value: text)]

        guard case .joinLoopSight(let parsed) = try DeepLinkParser().parseDeepLink(url: components.url!) else {
            return XCTFail("not a join link")
        }
        XCTAssertEqual(parsed.invitationLink, LoopSightInvitationLink(text))
    }

    /// Open, accept, be confirmed by Loop, then read the circle as this caregiver.
    func testJoinAgainstADemoNode() async throws {
        guard let text = ProcessInfo.processInfo.environment["LOOPSIGHT_INVITE"], let link = LoopSightInvitationLink(text) else {
            throw XCTSkip("Set LOOPSIGHT_INVITE to a demo node's invitation link.")
        }
        let client = LoopSightClient(key: CaregiverKey.generate())
        let invitation = try await client.open(link)
        XCTAssertEqual(invitation.status, "pending")
        XCTAssertNil(invitation.acceptedBy)
        XCTAssertFalse(invitation.nickname.isEmpty)

        try await client.accept(invitation)
        let reopened = try await client.open(link)
        XCTAssertEqual(reopened.acceptedBy, client.key.keyID)

        // The demo's Loop confirms once a minute; until then the circle refuses this caregiver.
        let credentials = LoopSightCredentials(siteURL: link.siteURL, circle: invitation.circle, keyID: client.key.keyID)
        var circle: LoopSightJSON?
        for _ in 0..<45 {
            do {
                circle = try await client.request(base: credentials.siteURL, method: "GET", path: "/v1/circles/\(credentials.circle)/circle")
                break
            } catch LoopSightClientError.badResponse(let status, _) where status == 401 || status == 403 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        let confirmed = try XCTUnwrap(circle, "Loop didn't confirm within 90 seconds")
        XCTAssertNotNil(confirmed["caregivers"]?.arrayValue?.first { $0["keyId"]?.stringValue == client.key.keyID })
    }
}
