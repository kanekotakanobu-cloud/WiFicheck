import SystemConfiguration

struct GatewayInfo {
    let router: String?
    let primaryInterface: String?
}

/// SystemConfigurationの動的ストアから、Wi-Fiインターフェースのデフォルトゲートウェイを得る。
enum GatewayResolver {
    private static let store = SCDynamicStoreCreate(nil, "WiFiSurvey" as CFString, nil, nil)

    static func resolve(interface: String?) -> GatewayInfo {
        guard let store = Self.store else { return GatewayInfo(router: nil, primaryInterface: nil) }

        let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String

        guard let interface else { return GatewayInfo(router: nil, primaryInterface: primary) }

        // 有線が優先経路の場合でも、Wi-Fiサービス側のRouterを探す
        if let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/IPv4" as CFString) as? [String] {
            for key in keys {
                guard let d = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                      d["InterfaceName"] as? String == interface,
                      let router = d["Router"] as? String
                else { continue }
                return GatewayInfo(router: router, primaryInterface: primary)
            }
        }
        if primary == interface, let router = global?["Router"] as? String {
            return GatewayInfo(router: router, primaryInterface: primary)
        }
        return GatewayInfo(router: nil, primaryInterface: primary)
    }
}
