import AppKit
import SwiftUI

/// A white symbol on a coloured rounded square, like the icons in System Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.26))
    }
}

/// The top of every Settings page: icon, title and one sentence saying what the page is for.
struct PageHeader: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, color: color, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

/// One Settings page: the header, then a grouped form underneath.
struct SettingsPage<Content: View>: View {
    let tab: SettingsView.Tab
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: tab.symbol, color: tab.color, title: tab.title, subtitle: tab.subtitle)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
    }
}

/// The keys of a shortcut drawn as keyboard keys: ⌥ Option  +  ⇧ Shift.
struct KeyCaps: View {
    let shortcut: DragShortcut
    var large = false

    private var keys: [(symbol: String, name: String)] {
        var keys: [(String, String)] = []
        if shortcut.flags.contains(.control) { keys.append(("⌃", "Control")) }
        if shortcut.flags.contains(.option) { keys.append(("⌥", "Option")) }
        if shortcut.flags.contains(.shift) { keys.append(("⇧", "Shift")) }
        return keys
    }

    var body: some View {
        HStack(spacing: large ? 8 : 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 { Text("+").font(large ? .title3 : .caption).foregroundStyle(.secondary) }
                VStack(spacing: 0) {
                    Text(key.symbol).font(.system(size: large ? 20 : 12, weight: .medium))
                    Text(key.name).font(.system(size: large ? 10 : 8, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(minWidth: large ? 62 : 40, minHeight: large ? 50 : 30)
                .padding(.horizontal, 4)
                .background(.background, in: .rect(cornerRadius: large ? 9 : 6))
                .overlay(RoundedRectangle(cornerRadius: large ? 9 : 6).strokeBorder(.separator))
                .shadow(color: .black.opacity(0.15), radius: 0, y: large ? 2 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.label)
    }
}

/// A selectable card with a small picture, used for choices you understand better by seeing them.
struct ChoiceCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 120, height: 76)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.lemonDeep : Color.secondary.opacity(0.25), lineWidth: isSelected ? 3 : 1))
                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.lemonDeep : .secondary)
                    Text(title)
                }
                .font(.callout)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small picture of the wheel in its glass or solid look.
struct WheelLookPreview: View {
    let appearance: AppSettings.Appearance

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.55), .purple.opacity(0.5), .orange.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<6) { index in
                Circle()
                    .trim(from: CGFloat(index) / 6 + 0.012, to: CGFloat(index + 1) / 6 - 0.012)
                    .stroke(appearance == .glass ? Color.white.opacity(0.55) : Color(white: 0.96), lineWidth: 16)
                    .frame(width: 50, height: 50)
            }
            Circle().fill(appearance == .glass ? Color.white.opacity(0.35) : Color(white: 0.85)).frame(width: 18, height: 18)
        }
    }
}

/// "12 free uses left · Buy" or "Licensed", pinned under the Settings sidebar.
struct LicenceBadge: View {
    @State private var license = LicenseManager.shared
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: !license.isLicensed ? "gift.fill" : license.needsOnlineCheck ? "wifi.exclamationmark" : "checkmark.seal.fill")
                    .foregroundStyle(!license.isLicensed ? Color.lemonDeep : license.needsOnlineCheck ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(license.statusText).font(.caption.weight(.semibold))
                        .lineLimit(1).fixedSize()
                    if !license.isLicensed { Text("Buy Lemon").font(.caption2).foregroundStyle(.secondary) }
                    if license.needsOnlineCheck { Text("Check Now").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}

/// Buying, activating and deactivating Lemon. Used by the purchase window and Settings → Licence.
struct LicencePanel: View {
    @State private var license = LicenseManager.shared
    @State private var key = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if license.isLicensed { licensed } else { trial }
        }
    }

    // MARK: Licensed

    @State private var checkMessage: String?

    private var licensed: some View {
        VStack(spacing: 12) {
            if license.needsOnlineCheck {
                Label("Lemon needs to confirm your licence", systemImage: "wifi.exclamationmark")
                    .font(.headline).foregroundStyle(.orange)
                Text("It hasn't been able to reach the licence server for 30 days. Connect to the internet, then click Check Now.")
                    .font(.callout).multilineTextAlignment(.center)
            } else {
                Label("Lemon is activated on this Mac", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
            }
            if let key = license.licenseKey {
                Text("Licence key ending in \(String(key.suffix(4)))").font(.callout).foregroundStyle(.secondary)
            }
            if !license.needsOnlineCheck {
                Text("Thank you for buying Lemon. Every feature is yours, with no limits.")
                    .font(.callout).multilineTextAlignment(.center)
            }
            if let lastChecked = license.lastChecked {
                Text("Last confirmed \(lastChecked.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(working ? "Checking…" : "Check Now", action: checkNow)
                    .buttonStyle(.glass).disabled(working)
                Button("Deactivate This Mac") {
                    Task { working = true; await license.deactivate(); working = false }
                }
                .buttonStyle(.glass).disabled(working)
            }
            if let checkMessage {
                Text(checkMessage).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text("Deactivate to move your licence to another Mac.").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Trial

    private var trial: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack {
                    Text("Free uses").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(license.usesLeft) of \(StoreConfig.freeUses) left").font(.callout).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(license.usesLeft), total: Double(StoreConfig.freeUses)).tint(.lemonDeep)
            }

            VStack(alignment: .leading, spacing: 9) {
                benefit("infinity", "Unlimited conversions and tools")
                benefit("wand.and.stars", "Every editor: crop, trim, redact, pages and more")
                benefit("creditcard", "Pay once. No subscription")
                benefit("lock.shield", "Your files never leave your Mac")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            BuyButtons()

            VStack(alignment: .leading, spacing: 6) {
                Text("Already bought Lemon?").font(.callout.weight(.medium))
                HStack {
                    TextField("Licence key", text: $key, prompt: Text("Licence key from your receipt email"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(activate)
                    Button(working ? "Checking…" : "Activate", action: activate)
                        .buttonStyle(.glass).disabled(working || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                HStack(spacing: 4) {
                    Text("Paid with UPI or Razorpay?").foregroundStyle(.secondary)
                    Link("Find your key", destination: StoreConfig.keyLookupURL)
                }
                .font(.caption)
            }
        }
    }

    private func checkNow() {
        working = true
        checkMessage = nil
        Task {
            switch await license.revalidate() {
            case .confirmed: checkMessage = "Confirmed. Thank you!"
            case .offline: checkMessage = "Couldn't reach the licence server. Check your internet connection."
            case .removed, .notLicensed: checkMessage = "This key is no longer valid on this Mac. Contact support if you think this is wrong."
            }
            working = false
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(Color.lemonDeep).frame(width: 20) }
    }

    private func activate() {
        guard !working, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
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

/// The ways to pay. Macs set to the India region see Razorpay (UPI, Indian cards) first;
/// everyone else sees Lemon Squeezy first. Both are one-time purchases.
struct BuyButtons: View {
    var body: some View {
        VStack(spacing: 8) {
            if StoreConfig.prefersRazorpay {
                buy("Buy with UPI or Card", price: StoreConfig.razorpayPriceText, url: StoreConfig.razorpayPageURL)
                other("Paying from outside India? Buy here", url: StoreConfig.checkoutURL)
            } else {
                buy("Buy Lemon", price: StoreConfig.priceText, url: StoreConfig.checkoutURL)
                other("In India? Pay with UPI", url: StoreConfig.razorpayPageURL)
            }
        }
    }

    private func buy(_ title: String, price: String?, url: URL) -> some View {
        Button(price.map { "\(title) · \($0), one time" } ?? title) { NSWorkspace.shared.open(url) }
            .buttonStyle(LemonButtonStyle())
    }

    private func other(_ title: String, url: URL) -> some View {
        Link(title, destination: url).font(.callout)
    }
}

/// The big yellow Buy button. Drawn by hand so it stays yellow with dark, readable text
/// even when the window isn't in front (system prominent buttons turn grey then).
struct LemonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.lemon.gradient, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.lemonDeep.opacity(0.6)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.capsule)
    }
}
