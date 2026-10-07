import AppKit
import CoreLocation

/// SSID/BSSID取得のための位置情報許可のみを扱う。位置座標は取得しない。
@MainActor
final class LocationAuthorizer: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var statusRaw: Int32
    private let manager: CLLocationManager

    override init() {
        let m = CLLocationManager()
        manager = m
        statusRaw = m.authorizationStatus.rawValue
        super.init()
        m.delegate = self
    }

    // CLAuthorizationStatus: 0=未決定 1=制限 2=拒否 3=常に許可 4=使用中のみ許可
    var isAuthorized: Bool { statusRaw == 3 || statusRaw == 4 }

    var label: String {
        switch statusRaw {
        case 0: return "未決定"
        case 1: return "制限あり"
        case 2: return "拒否"
        case 3: return "許可"
        case 4: return "許可（使用中）"
        default: return "不明(\(statusRaw))"
        }
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let raw = manager.authorizationStatus.rawValue
        Task { @MainActor in self.statusRaw = raw }
    }
}
