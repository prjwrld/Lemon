import AppKit
import SwiftUI

/// Opens the purchase / licence window (one at a time).
enum PurchaseWindow {
    private static var window: GlassWindow?

    static func show(reason: String? = nil) {
        if let window { window.present(); return }
        let window = GlassWindow(size: CGSize(width: 440, height: 620)) {
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

    var body: some View {
        GlassShell(title: license.isLicensed ? "Your Licence" : "Get Lemon", onClose: onClose) {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 88, height: 88)
                    Text(license.isLicensed ? "Lemon" : "Buy once, use forever").font(.title.bold())
                    if let reason, !license.isLicensed {
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
