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
    static let supportEmail = "support@example.com"
    static var supportURL: URL { URL(string: "mailto:\(supportEmail)")! }
    /// The exact FFmpeg source Lemon's media helper is built from (see scripts/build-ffmpeg.sh).
    static let ffmpegSourceURL = URL(string: "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz")!
    /// How many conversions or tools people can use before buying.
    static let freeUses = 15
}

/// Trial uses and the licence key. Both live in the Keychain, so they survive reinstalling.
@Observable
final class LicenseManager {
    static let shared = LicenseManager()

    private(set) var usesLeft: Int
    private(set) var licenseKey: String?
    private(set) var instanceID: String?

    var isLicensed: Bool { licenseKey != nil }
    var canUse: Bool { isLicensed || usesLeft > 0 }

    private init() {
        usesLeft = Keychain.read("usesLeft").flatMap(Int.init) ?? StoreConfig.freeUses
        licenseKey = Keychain.read("licenseKey")
        instanceID = Keychain.read("instanceID")
    }

    /// Counts one finished conversion or tool, while on the trial.
    func recordUse() {
        guard !isLicensed, usesLeft > 0 else { return }
        usesLeft -= 1
        Keychain.write("usesLeft", String(usesLeft))
    }

    var statusText: String {
        if isLicensed { return "Licensed" }
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
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LemonError("Enter the licence key from your receipt email.") }
        let response = try await post("activate", ["license_key": key, "instance_name": Host.current().localizedName ?? "Mac"])
        guard response.activated == true, let instance = response.instance else {
            throw LemonError(response.error ?? "That licence key wasn't accepted.")
        }
        if let expected = StoreConfig.productID, response.meta?.product_id != expected {
            throw LemonError("That key is for a different product.")
        }
        licenseKey = key
        instanceID = instance.id
        Keychain.write("licenseKey", key)
        Keychain.write("instanceID", instance.id)
    }

    /// Frees this Mac's activation so the key can be used on another Mac.
    func deactivate() async {
        if let key = licenseKey, let instanceID {
            _ = try? await post("deactivate", ["license_key": key, "instance_id": instanceID])
        }
        licenseKey = nil
        instanceID = nil
        Keychain.delete("licenseKey")
        Keychain.delete("instanceID")
    }

    /// Checks that the key is still valid for this Mac: not made up, refunded, disabled,
    /// deactivated from another place, or for a different product. If Lemon Squeezy says no,
    /// the licence is removed. If it can't be reached (offline), the licence is kept.
    func revalidate() async {
        guard let key = licenseKey, let instanceID,
              let response = try? await post("validate", ["license_key": key, "instance_id": instanceID])
        else { return }
        let wrongProduct = StoreConfig.productID.map { response.meta?.product_id != $0 } ?? false
        if response.valid == false || wrongProduct {
            licenseKey = nil
            self.instanceID = nil
            Keychain.delete("licenseKey")
            Keychain.delete("instanceID")
        }
    }

    private func post(_ action: String, _ fields: [String: String]) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(action)")!)
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
