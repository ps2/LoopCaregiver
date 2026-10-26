//
//  LoopCareJoinView.swift
//  LoopCaregiver
//
//  Join a child's LoopCare circle with the invitation link Loop shared:
//  paste or scan it, see what it offers, and accept.
//

import CodeScanner
import LoopCaregiverKit
import SwiftUI

struct LoopCareJoinView: View {
    @ObservedObject var accountService: AccountServiceManager
    /// An invitation that opened the app; it's opened at once.
    var initialLink: LoopCareInvitationLink?
    /// After joining.
    var onJoined: () -> Void
    @State private var linkText = ""
    @State private var invitation: LoopCareInvitation?
    @State private var nameText = ""
    @State private var errorText: String?
    @State private var working = false
    @State private var isShowingScanner = false

    var body: some View {
        VStack {
            Form {
                if let invitation {
                    offerSection(invitation)
                } else {
                    Section {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("Scan the Code from Loop", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } footer: {
                        Text("Loop invites you: on the Looper's phone, Settings → Services → LoopCare → Invite. Scan the code it shows, or open the link it sends you.")
                    }
                    Section {
                        TextField("https://…/i/…#…", text: $linkText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit(open)
                        // Reads the clipboard only when tapped, so iOS doesn't ask for permission.
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in linkText = text; open() }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleOnly)
                    } header: {
                        Text("Or the invitation link")
                    }
                }
            }
            if working {
                ProgressView()
            }
            Spacer()
            if invitation != nil {
                Button("Join") { join() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .disabled(working || nameText.isEmpty)
            }
            if let errorText {
                Text(errorText).foregroundColor(.red).padding(.horizontal)
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            CodeScannerView(codeTypes: [.qr]) { result in
                isShowingScanner = false
                if case .success(let scan) = result { linkText = scan.string; open() }
            }
        }
        .onChange(of: linkText) { _ in
            if invitation != nil && invitation?.link != LoopCareInvitationLink(anyLink: linkText) { invitation = nil }
        }
        .onAppear {
            if let initialLink, linkText.isEmpty {
                linkText = initialLink.text
                open()
            }
        }
    }

    private func offerSection(_ invitation: LoopCareInvitation) -> some View {
        Section {
            TextField("Name", text: $nameText)
            LabeledContent("You", value: invitation.nickname)
            if let visibility = invitation.visibility {
                LabeledContent("Sees", value: Self.visibilityText[visibility] ?? visibility)
            }
            ForEach(["meals", "bolus", "adjustments"], id: \.self) { area in
                LabeledContent(area.capitalized, value: Self.levelText[invitation.areas[area] ?? "none"] ?? "—")
            }
            if invitation.status != "pending" {
                Text(Self.statusText[invitation.status] ?? invitation.status).foregroundColor(.secondary)
            }
        } header: {
            Text(invitation.name.map { "Join \($0)'s circle" } ?? "Join this circle")
        } footer: {
            Text("After you join, Loop confirms you on their phone. Until then you'll see “Waiting for Loop”.")
        }
    }

    private func open() {
        guard let link = LoopCareInvitationLink(anyLink: linkText) else {
            errorText = LoopCareClientError.invalidLink.localizedDescription
            return
        }
        run {
            let opened = try await LoopCareClient(key: try CaregiverKeyStore.loadOrCreate()).open(link)
            invitation = opened
            if nameText.isEmpty { nameText = opened.name ?? "" }
        }
    }

    private func join() {
        guard let invitation else { return }
        run {
            _ = try await accountService.join(invitation, name: nameText.trimmingCharacters(in: .whitespacesAndNewlines))
            onJoined()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task { @MainActor in
            errorText = nil
            working = true
            do { try await work() } catch { errorText = error.localizedDescription }
            working = false
        }
    }

    static let visibilityText = ["full": "Everything", "summary": "A summary", "safetyNet": "Urgent alerts only", "review": "Reports only"]
    static let levelText = ["none": "No", "approval": "With Loop's approval", "notify": "Yes, and Loop is told", "full": "Yes"]
    static let statusText = [
        "accepted": "Already accepted, waiting for Loop to confirm.",
        "confirmed": "Already accepted and confirmed.",
        "cancelled": "This invitation was cancelled.",
        "expired": "This invitation has expired.",
    ]
}
