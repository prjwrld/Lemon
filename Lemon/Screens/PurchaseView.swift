import AppKit
import SwiftUI

/// Opens the purchase / licence window (one at a time).
enum PurchaseWindow {
    private static var window: GlassWindow?

    static func show(reason: String? = nil) {
        if let window { window.present(); return }
        let window = GlassWindow(size: CGSize(width: 420, height: 560)) {
            PurchaseView(reason: reason, onClose: { PurchaseWindow.close() })
        }
        window.onClose = { PurchaseWindow.window = nil }
        self.window = window
        window.present()
    }

    static func close() { window?.close() }
}

struct PurchaseView: View {
    var reason: String?
    let onClose: () -> Void

    @State private var license = LicenseManager.shared
    @State private var key = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        GlassShell(title: license.isLicensed ? "Your Licence" : "Get Lemon", onClose: onClose) {
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                VStack(spacing: 4) {
                    Text("Lemon").font(.largeTitle.bold())
                    Text(reason ?? license.statusText)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    benefit("infinity", "Unlimited conversions and tools")
                    benefit("wand.and.stars", "Every editor: crop, trim, photo, pages and more")
                    benefit("lock.shield", "Everything stays on your Mac")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                if license.isLicensed {
                    Label("This Mac is activated", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.headline)
                    Button("Deactivate This Mac") {
                        Task { working = true; await license.deactivate(); working = false }
                    }
                    .buttonStyle(.glass).disabled(working)
                } else {
                    Button { NSWorkspace.shared.open(StoreConfig.checkoutURL) } label: {
                        Text("Buy Lemon").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(.lemonDeep).controlSize(.extraLarge)

                    HStack {
                        TextField("Licence key", text: $key).textFieldStyle(.roundedBorder)
                            .onSubmit(activate)
                        Button(working ? "Checking…" : "Activate", action: activate)
                            .buttonStyle(.glass).disabled(working || key.isEmpty)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Text("Already bought it? Enter the key from your receipt to restore your purchase.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
        } footer: {
            HStack(spacing: 14) {
                Link("Privacy", destination: StoreConfig.privacyURL)
                Link("Terms", destination: StoreConfig.termsURL)
                Link("Support", destination: URL(string: "mailto:\(StoreConfig.supportEmail)")!)
            }
            .font(.caption)
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(Color.lemonDeep) }
    }

    private func activate() {
        guard !working, !key.isEmpty else { return }
        working = true
        error = nil
        Task {
            do {
                try await license.activate(key)
                key = ""
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            working = false
        }
    }
}
