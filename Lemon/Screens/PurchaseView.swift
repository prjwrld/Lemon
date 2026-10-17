import AppKit
import SwiftUI

/// Opens the purchase / licence window (one at a time).
enum PurchaseWindow {
    private static var window: GlassWindow?

    static func show() {
        if let window { window.present(); return }
        let window = GlassWindow(size: CGSize(width: 440, height: 620)) {
            PurchaseView(onClose: { PurchaseWindow.close() })
        }
        window.onClose = { PurchaseWindow.window = nil }
        self.window = window
        window.present()
    }

    static func close() { window?.close() }
}

struct PurchaseView: View {
    let onClose: () -> Void

    @State private var license = LicenseManager.shared

    /// Why Lemon stopped, worked out from the current state so it's never out of date.
    /// (A licence that needs checking explains itself in the panel below.)
    private var reason: String? {
        if !license.isLicensed && license.usesLeft == 0 {
            return "You've used all \(StoreConfig.freeUses) free uses. Buy Lemon once to keep going."
        }
        return nil
    }

    var body: some View {
        GlassShell(title: license.isLicensed ? "Your Licence" : "Get Lemon", onClose: onClose) {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 88, height: 88)
                    Text(license.isLicensed ? "Lemon" : "Buy once, use forever").font(.title.bold())
                    if let reason {
                        Text(reason).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                LicencePanel()
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                Spacer(minLength: 0)
            }
        } footer: {
            HStack(spacing: 16) {
                Link("Privacy", destination: StoreConfig.privacyURL)
                Link("Terms", destination: StoreConfig.termsURL)
                Link("Support", destination: StoreConfig.supportURL)
            }
            .font(.caption)
        }
    }
}
