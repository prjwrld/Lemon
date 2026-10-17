import AppKit
import Observation
import Security

/// Every link and store detail Lemon uses, in one place. Fill these in before release
/// (every "example" value is a placeholder):
/// Lemon Squeezy → Products → your product → Share → copy the checkout link and the product ID.
enum StoreConfig {
    static let checkoutURL = URL(string: "https://example.lemonsqueezy.com/buy/REPLACE-WITH-YOUR-CHECKOUT-ID")!
    /// Only keys for this product are accepted. Set it before release (nil accepts any product).
    static let productID: Int? = nil
    /// Shown on the Buy button, e.g. "$12". nil shows no price.
    static let priceText: String? = nil
    static let websiteURL = URL(string: "https://example.com/lemon")!
    static let privacyURL = URL(string: "https://example.com/lemon/privacy")!
    static let termsURL = URL(string: "https://example.com/lemon/terms")!
    static let supportEmail = "support@fixbyai.in"
    static var supportURL: URL { URL(string: "mailto:\(supportEmail)")! }
    /// The exact FFmpeg source Lemon's media helper is built from (see scripts/build-ffmpeg.sh).
    static let ffmpegSourceURL = URL(string: "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz")!
    /// How many conversions or tools people can use before buying.
    static let freeUses = 15

    // MARK: India: Razorpay (see Server/README.md)
    /// Your Razorpay Payment Page for Lemon (one link many people can pay through).
    static let razorpayPageURL = URL(string: "https://pages.razorpay.com/REPLACE-WITH-YOUR-PAGE")!
    /// Shown on the India Buy button, e.g. "₹499". nil shows no price.
    static let razorpayPriceText: String? = "₹799"
    /// Lemon's own key server (Server/), which makes and checks the keys of Razorpay buyers.
    static let keyServerURL = URL(string: "https://lemon-licences.edupurspose.workers.dev")!
    /// "Find my key" page on the key server, for Razorpay buyers.
    static var keyLookupURL: URL { keyServerURL.appendingPathComponent("key") }

    /// Keys from Lemon's own server (Razorpay purchases) look like LEMON-XXXXX-XXXXX-XXXXX-XXXXX;
    /// all other keys come from Lemon Squeezy.
    static func isOwnServerKey(_ key: String) -> Bool { key.uppercased().hasPrefix("LEMON-") }

    /// Shows the India (Razorpay) way to pay first on Macs set to the India region.
    static var prefersRazorpay: Bool { Locale.current.region == .india }
    /// Where the main Buy button goes.
    static var preferredBuyURL: URL { prefersRazorpay ? razorpayPageURL : checkoutURL }
}

/// Free uses and the licence key. Both live in the Keychain, so they survive reinstalling.
@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    /// How long Lemon keeps working without being able to confirm the licence online.
    static let offlineGrace: TimeInterval = 30 * 24 * 3600
    /// How often Lemon re-checks the licence while it runs.
    static let checkInterval: TimeInterval = 24 * 3600

    private(set) var usesLeft: Int
    private(set) var licenseKey: String?
    private(set) var instanceID: String?
    /// When Lemon Squeezy last confirmed the key for this Mac.
    private(set) var lastChecked: Date?

    var isLicensed: Bool { licenseKey != nil }

    /// Licensed, but the key hasn't been confirmed online for too long (or the clock was moved back).
    var needsOnlineCheck: Bool {
        guard isLicensed, let lastChecked else { return false }
        let age = Date().timeIntervalSince(lastChecked)
        return age > Self.offlineGrace || age < -24 * 3600
    }

    var canUse: Bool { isLicensed ? !needsOnlineCheck : usesLeft > 0 }

    private init() {
        usesLeft = FreeUses.read() ?? StoreConfig.freeUses
        licenseKey = Keychain.read("licenseKey")
        instanceID = Keychain.read("instanceID")
        lastChecked = Keychain.read("lastChecked").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        // Licences from before the regular checks start their 30 days now.
        if isLicensed && lastChecked == nil { markChecked() }
        // Put back any copy of the free-use count that was deleted.
        FreeUses.write(usesLeft)
    }

    /// Counts one finished conversion or tool, while on the trial.
    func recordUse() {
        guard !isLicensed, usesLeft > 0 else { return }
        usesLeft -= 1
        FreeUses.write(usesLeft)
    }

    var statusText: String {
        if isLicensed { return needsOnlineCheck ? "Licence needs checking" : "Licensed" }
        if usesLeft == 0 { return "Free uses used up" }
        return usesLeft == 1 ? "1 free use left" : "\(usesLeft) free uses left"
    }

    // MARK: Lemon Squeezy licence API (https://docs.lemonsqueezy.com/api/license-api)

    private struct Response: Decodable {
        struct Instance: Decodable { let id: String }
        struct Meta: Decodable { let product_id: Int? }
        struct Key: Decodable { let status: String? }
        let activated: Bool?
        let valid: Bool?
        let error: String?
        let instance: Instance?
        let meta: Meta?
        let license_key: Key?
    }

    /// Activates a key for this Mac. Throws a readable message if it's not accepted.
    func activate(_ rawKey: String) async throws {
        var key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if StoreConfig.isOwnServerKey(key) { key = key.uppercased() }
        guard !key.isEmpty else { throw LemonError("Enter the licence key from your receipt email.") }
        let response = try await post("activate", ["license_key": key, "instance_name": Host.current().localizedName ?? "Mac"])
        guard response.activated == true, let instance = response.instance else {
            throw LemonError(response.error ?? "That licence key wasn't accepted.")
        }
        if !StoreConfig.isOwnServerKey(key), let expected = StoreConfig.productID, response.meta?.product_id != expected {
            // Give the activation back, so the key's owner doesn't lose a Mac slot.
            _ = try? await post("deactivate", ["license_key": key, "instance_id": instance.id])
            throw LemonError("That key is for a different product.")
        }
        licenseKey = key
        instanceID = instance.id
        Keychain.write("licenseKey", key)
        Keychain.write("instanceID", instance.id)
        markChecked()
    }

    /// Frees this Mac's activation so the key can be used on another Mac.
    func deactivate() async {
        if let key = licenseKey, let instanceID {
            _ = try? await post("deactivate", ["license_key": key, "instance_id": instanceID])
        }
        removeLicence()
    }

    enum CheckResult { case confirmed, removed, offline, notLicensed }

    /// Checks that the key is still valid for this Mac: not made up, refunded, disabled,
    /// deactivated from another place, or for a different product. If Lemon Squeezy says no,
    /// the licence is removed. If it can't be reached (offline), the licence is kept, for up to
    /// `offlineGrace` since the last successful check.
    @discardableResult
    func revalidate() async -> CheckResult {
        guard let key = licenseKey, let instanceID else { return .notLicensed }
        guard let response = try? await post("validate", ["license_key": key, "instance_id": instanceID]),
              let valid = response.valid
        else { return .offline }
        let wrongProduct = !StoreConfig.isOwnServerKey(key) && (StoreConfig.productID.map { response.meta?.product_id != $0 } ?? false)
        guard valid, !wrongProduct else {
            removeLicence()
            return .removed
        }
        markChecked()
        return .confirmed
    }

    /// Re-checks if the last check is more than a day old. Called at launch and every few hours.
    func revalidateIfDue() async {
        guard isLicensed else { return }
        if let lastChecked, abs(Date().timeIntervalSince(lastChecked)) < Self.checkInterval { return }
        await revalidate()
    }

    private func markChecked() {
        lastChecked = Date()
        Keychain.write("lastChecked", String(lastChecked!.timeIntervalSince1970))
    }

    private func removeLicence() {
        licenseKey = nil
        instanceID = nil
        lastChecked = nil
        Keychain.delete("licenseKey")
        Keychain.delete("instanceID")
        Keychain.delete("lastChecked")
    }

    #if DEBUG
    /// Test helpers (see AppDelegate's -LemonTest… options).
    func debugSetUsesLeft(_ value: Int) {
        usesLeft = value
        FreeUses.write(value)
    }

    func debugSetLastChecked(daysAgo: Double) {
        lastChecked = Date(timeIntervalSinceNow: -daysAgo * 24 * 3600)
        Keychain.write("lastChecked", String(lastChecked!.timeIntervalSince1970))
    }
    #endif

    private func post(_ action: String, _ fields: [String: String]) async throws -> Response {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "LemonTestOffline") {
            throw LemonError("Couldn't reach the licence server. Check your internet connection.")
        }
        #endif
        // Razorpay keys are checked by Lemon's own server, all others by Lemon Squeezy (same API).
        var server = URL(string: "https://api.lemonsqueezy.com")!
        if StoreConfig.isOwnServerKey(fields["license_key"] ?? "") {
            server = StoreConfig.keyServerURL
            #if DEBUG
            if let test = UserDefaults.standard.string(forKey: "LemonTestKeyServer"), let url = URL(string: test) { server = url }
            #endif
        }
        var request = URLRequest(url: server.appendingPathComponent("v1/licenses/\(action)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(Response.self, from: data)
        } catch is DecodingError {
            throw LemonError("The licence server sent an unexpected reply. Please try again.")
        } catch {
            throw LemonError("Couldn't reach the licence server. Check your internet connection.")
        }
    }
}

/// The free-use count is kept in three places and the lowest number wins, so deleting one
/// of them (for example Lemon's item in Keychain Access) doesn't give back 15 free uses.
/// Raising a number by hand doesn't help either, since the lowest copy still counts.
enum FreeUses {
    #if DEBUG
    private static let prefix = "debug."
    #else
    private static let prefix = ""
    #endif
    private static let defaultsKey = prefix + "wheel.layoutCache"
    private static let file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lemon/.\(prefix)wheel-cache")

    static func read() -> Int? {
        let copies = [
            Keychain.read("usesLeft").flatMap(Int.init),
            UserDefaults.standard.object(forKey: defaultsKey) as? Int,
            (try? String(contentsOf: file, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) },
        ]
        return copies.compactMap { $0 }.min().map { max(0, min($0, StoreConfig.freeUses)) }
    }

    static func write(_ value: Int) {
        Keychain.write("usesLeft", String(value))
        UserDefaults.standard.set(value, forKey: defaultsKey)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? String(value).write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Small wrapper around the Keychain for a few strings.
/// Debug builds are re-signed on every build, so macOS would ask for the Keychain password
/// each launch; they keep these values in UserDefaults instead.
enum Keychain {
    private static let service = "com.prajwal.Lemon.license"

    static func read(_ account: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "debug.keychain.\(account)")
        #else
        return readKeychain(account)
        #endif
    }

    static func write(_ account: String, _ value: String) {
        #if DEBUG
        UserDefaults.standard.set(value, forKey: "debug.keychain.\(account)")
        #else
        writeKeychain(account, value)
        #endif
    }

    static func delete(_ account: String) {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: "debug.keychain.\(account)")
        #else
        deleteKeychain(account)
        #endif
    }

    private static func readKeychain(_ account: String) -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ account: String, _ value: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        let data = Data(value.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func deleteKeychain(_ account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
}
