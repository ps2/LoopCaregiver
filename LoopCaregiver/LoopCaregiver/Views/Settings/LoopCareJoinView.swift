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
    @Binding var path: NavigationPath
    @State private var linkText = ""
    @State private var invitation: LoopCareInvitation?
    @State private var nameText = ""
    @State private var errorText: String?
    @State private var working = false
    @State private var isShowingScanner = false

    var body: some View {
        VStack {
            Form {
                Section {
                    TextField("https://…/i/…#…", text: $linkText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(open)
                    HStack {
                        // Reads the clipboard only when tapped, so iOS doesn't ask for permission.
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in linkText = text; open() }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleOnly)
                        Spacer()
                        Button("Scan QR") { isShowingScanner = true }
                            .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Invitation link")
                } footer: {
                    Text("The link Loop shared with you from Settings → Services → LoopCare.")
                }
                if let invitation {
                    offerSection(invitation)
                }
            }
            if working {
                ProgressView()
            }
            Spacer()
            Button(invitation == nil ? "Open Invitation" : "Join") {
                invitation == nil ? open() : join()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding()
            .disabled(working || linkText.isEmpty || (invitation != nil && nameText.isEmpty))
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
            if invitation != nil && invitation?.link != LoopCareInvitationLink(linkText) { invitation = nil }
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
        guard let link = LoopCareInvitationLink(linkText) else {
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
            if !path.isEmpty { path.removeLast() }
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
